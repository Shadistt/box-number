import Foundation
import UIKit
import PDFKit
import Supabase

/// PDF документов (03.11.2026): локально рядом с фото (<id>.pdf), в R2 — items/<id>/doc.pdf.
/// У сейфа на диск и в R2 уходят зашифрованные байты (AES-GCM, ключ сейфа), как у фото.
/// Страницы (JPEG) храним локально отдельно, чтобы «досканировать» без пересборки из PDF.
enum DocStore {
    private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("docs", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func pdfURL(_ id: UUID) -> URL { dir.appendingPathComponent(id.uuidString + ".pdf") }
    private static func pagesDir(_ id: UUID) -> URL {
        let d = dir.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Страницы документа по порядку (JPEG; у сейфа — расшифрованные).
    static func pages(_ id: UUID, encrypted: Bool) -> [Data] {
        let d = pagesDir(id)
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasSuffix(".page") }.sorted()
        return files.compactMap { f in
            guard let data = try? Data(contentsOf: d.appendingPathComponent(f)) else { return nil }
            return encrypted ? SafeSession.shared.decrypt(data) : data
        }
    }

    /// Добавить страницу и пересобрать PDF. Возвращает (pdf для загрузки — уже зашифрованный, если сейф; число страниц).
    static func append(_ jpeg: Data, to id: UUID, encrypted: Bool) -> (pdf: Data, pages: Int)? {
        let d = pagesDir(id)
        let n = ((try? FileManager.default.contentsOfDirectory(atPath: d.path)) ?? []).filter { $0.hasSuffix(".page") }.count
        let stored = encrypted ? (try? SafeSession.shared.encrypt(jpeg)) : jpeg
        guard let stored else { return nil }
        try? stored.write(to: d.appendingPathComponent(String(format: "%04d.page", n)), options: .atomic)
        let all = pages(id, encrypted: encrypted)
        let pdf = DocScanner.pdf(from: all)
        let out = encrypted ? (try? SafeSession.shared.encrypt(pdf)) : pdf
        guard let out else { return nil }
        try? out.write(to: pdfURL(id), options: .atomic)
        return (out, all.count)
    }

    /// PDF для просмотра и «Поделиться»: локальный файл или скачиваем по подписанной ссылке. У сейфа — расшифровка.
    static func pdf(for item: Item) async -> Data? {
        let url = pdfURL(item.id)
        var data = try? Data(contentsOf: url)
        if data == nil, let key = item.doc {
            struct Ticket: Decodable { let url: String }
            if let t: Ticket = try? await supabase.functions.invoke("photo-view-url", options: .init(body: ["key": key])),
               let (d, _) = try? await URLSession.shared.data(from: URL(string: t.url)!) {
                try? d.write(to: url, options: .atomic); data = d
            }
        }
        guard let data else { return nil }
        if item.isEncrypted {
            guard await SafeSession.shared.isOpen else { return nil }
            return SafeSession.shared.decrypt(data)
        }
        return data
    }

    /// Загрузка PDF в R2 (тикет — та же функция, что для фото, с doc: true).
    static func upload(_ id: UUID, pdf: Data, pages: Int, store: PlacesStore) async {
        struct Ticket: Decodable { let doc_key: String?; let doc_url: String? }
        do {
            let t: Ticket = try await supabase.functions.invoke("photo-upload-url", options: .init(body: ["item_id": id.uuidString, "doc": "1"]))
            guard let key = t.doc_key, let u = t.doc_url, let url = URL(string: u) else { return }
            var req = URLRequest(url: url); req.httpMethod = "PUT"
            req.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
            let (_, resp) = try await URLSession.shared.upload(for: req, from: pdf)
            guard (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else { return }
            try await store.updateDocument(id, key: .some(key), pages: pages)
        } catch { print("doc upload:", error) }
    }

    /// Перед «Досканировать» на другом телефоне: страниц локально нет — достаём их из PDF, чтобы новые легли после старых.
    static func ensurePages(_ item: Item) async {
        guard pages(item.id, encrypted: item.isEncrypted).isEmpty, let pdf = await pdf(for: item),
              let doc = PDFDocument(data: pdf) else { return }
        let d = pagesDir(item.id)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            let scale = 1800 / max(b.width, b.height)
            let img = page.thumbnail(of: CGSize(width: b.width * scale, height: b.height * scale), for: .mediaBox)
            guard let jpeg = img.jpegData(compressionQuality: 0.6) else { continue }
            let stored = item.isEncrypted ? (try? SafeSession.shared.encrypt(jpeg)) : jpeg
            try? stored?.write(to: d.appendingPathComponent(String(format: "%04d.page", i)), options: .atomic)
        }
    }

    /// Временный файл для «Поделиться» (расшифрованный; удаляется системой из tmp).
    static func shareFile(_ pdf: Data, title: String) -> URL? {
        let safe = title.isEmpty ? "Документ" : title.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).pdf")
        do { try pdf.write(to: url, options: .atomic); return url } catch { return nil }
    }
}
