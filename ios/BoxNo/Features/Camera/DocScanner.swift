import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import AVFoundation
import Observation

/// Документы в обычной камере (утверждено 03.11.2026): если в кадре лист — подсвечиваем края,
/// снимок выравниваем по углам и складываем в PDF. Всё на устройстве (Vision), сеть не нужна.
@MainActor
@Observable
final class DocDetector {
    static let shared = DocDetector()
    /// Углы листа в координатах устройства захвата (0…1, начало слева сверху, как у AVCapture); nil — листа нет.
    var quad: [CGPoint]? = nil
    /// Лист держится в кадре стабильно (несколько кадров подряд) — только тогда считаем, что это документ.
    var isDocument: Bool { quad != nil && streak >= 3 }
    private(set) var streak = 0

    /// Вызывается из очереди камеры примерно 6 раз в секунду, только пока открыта полноэкранная камера.
    nonisolated func process(_ buffer: CVPixelBuffer) {
        let req = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        try? handler.perform([req])
        let obs = (req.results)?.first
        // Мелкие и неуверенные находки отбрасываем: это может быть этикетка на коробке, а не лист.
        let found: [CGPoint]? = obs.flatMap { o in
            guard o.confidence > 0.6, area(o) > 0.12 else { return nil }
            // Vision: начало слева снизу → устройство захвата: слева сверху
            return [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft].map { CGPoint(x: $0.x, y: 1 - $0.y) }
        }
        Task { @MainActor in
            if let found { self.streak += 1; self.quad = found } else { self.streak = 0; self.quad = nil }
        }
    }

    func reset() { quad = nil; streak = 0 }

    private nonisolated func area(_ o: VNRectangleObservation) -> Double {
        // площадь четырёхугольника по формуле шнурования
        let p = [o.topLeft, o.topRight, o.bottomRight, o.bottomLeft]
        var s = 0.0
        for i in 0..<4 { let a = p[i], b = p[(i + 1) % 4]; s += Double(a.x * b.y - b.x * a.y) }
        return abs(s) / 2
    }
}

enum DocScanner {
    /// Находит лист на снимке и выравнивает перспективу (CIPerspectiveCorrection). Нет листа — nil.
    static func extractPage(from image: UIImage) async -> UIImage? {
        await Task.detached(priority: .userInitiated) { () -> UIImage? in
            // Работаем с уже повёрнутой картинкой: так углы и пиксели в одной системе координат.
            let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
            let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(at: .zero) }
            guard let cg = upright.cgImage else { return nil }
            let req = VNDetectDocumentSegmentationRequest()
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            guard let o = req.results?.first, o.confidence > 0.5 else { return nil }
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            func px(_ p: CGPoint) -> CIVector { CIVector(cgPoint: CGPoint(x: p.x * w, y: p.y * h)) }   // CI: начало слева снизу, как у Vision
            let f = CIFilter.perspectiveCorrection()
            f.inputImage = CIImage(cgImage: cg)
            f.topLeft = px(o.topLeft).cgPointValue; f.topRight = px(o.topRight).cgPointValue
            f.bottomLeft = px(o.bottomLeft).cgPointValue; f.bottomRight = px(o.bottomRight).cgPointValue
            guard var out = f.outputImage else { return nil }
            // Чуть контраста — текст читается лучше, бумага светлее (без «ксерокса»).
            let c = CIFilter.colorControls(); c.inputImage = out; c.contrast = 1.12; c.brightness = 0.02; c.saturation = 0.9
            out = c.outputImage ?? out
            let ctx = CIContext()
            guard let res = ctx.createCGImage(out, from: out.extent) else { return nil }
            return UIImage(cgImage: res)
        }.value
    }

    /// Страница для PDF: до 1800 px по длинной стороне, JPEG ~0,6 — текст чёткий, ~150–250 КБ на страницу.
    static func pageJPEG(_ page: UIImage) -> Data? { page.resized(maxSide: 1800).jpegData(compressionQuality: 0.6) }

    /// Собирает PDF из JPEG-страниц. Картинки из JPEG Core Graphics кладёт в PDF без пережатия.
    static func pdf(from pages: [Data]) -> Data {
        let images = pages.compactMap { UIImage(data: $0) }
        guard let first = images.first else { return Data() }
        // Страница — по пропорциям листа, ширина как у A4 в пунктах (595).
        func bounds(_ i: UIImage) -> CGRect { CGRect(x: 0, y: 0, width: 595, height: 595 * i.size.height / max(i.size.width, 1)) }
        let r = UIGraphicsPDFRenderer(bounds: bounds(first))
        return r.pdfData { ctx in
            for img in images {
                let b = bounds(img)
                ctx.beginPage(withBounds: b, pageInfo: [:])
                img.draw(in: b)
            }
        }
    }

    /// Подсказки названия по тексту первой страницы (не для сейфа). Сначала известные виды документов, потом заголовок.
    static func titleSuggestions(_ page: UIImage) async -> [String] {
        await Task.detached(priority: .utility) { () -> [String] in
            guard let cg = page.cgImage else { return [] }
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.recognitionLanguages = ["ru-RU", "uk-UA", "en-US", "de-DE"]
            req.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 3 }
            let text = lines.joined(separator: " ").lowercased()
            var out: [String] = []
            for (keys, title) in known where keys.contains(where: { text.contains($0) }) { out.append(title) }
            // Заголовок: первая «словесная» строка из верхней части листа, не длиннее 40 символов.
            if let head = lines.prefix(6).first(where: { l in l.count <= 40 && l.filter(\.isLetter).count >= 4 && !l.contains("@") }) {
                let t = head.prefix(1).uppercased() + head.dropFirst().lowercased()
                if !out.contains(where: { $0.lowercased() == t.lowercased() }) { out.append(t) }
            }
            return Array(Captioner.dedupe(out).prefix(3))
        }.value
    }

    private static let known: [([String], String)] = [
        (["паспорт", "passport", "reisepass"], "Паспорт"),
        (["свидетельство о рождении", "свідоцтво про народження", "birth certificate", "geburtsurkunde"], "Свидетельство о рождении"),
        (["свидетельство о браке", "свідоцтво про шлюб", "marriage certificate"], "Свидетельство о браке"),
        (["договор аренды", "договір оренди", "lease agreement", "mietvertrag"], "Договор аренды"),
        (["договор", "договір", "agreement", "contract", "vertrag"], "Договор"),
        (["счёт", "счет-фактура", "рахунок", "invoice", "rechnung"], "Счёт"),
        (["справка", "довідка", "bescheinigung", "certificate"], "Справка"),
        (["полис", "поліс", "insurance", "versicherung"], "Страховой полис"),
        (["диплом", "diploma", "zeugnis"], "Диплом"),
        (["водительское удостоверение", "посвідчення водія", "driving licence", "driver license", "führerschein"], "Водительское удостоверение"),
        (["доверенность", "довіреність", "power of attorney", "vollmacht"], "Доверенность"),
        (["медицинск", "медичн", "medical", "ärztlich"], "Медицинский документ"),
        (["гарантийный талон", "гарантійний талон", "warranty", "garantie"], "Гарантийный талон"),
        (["чек", "receipt", "quittung", "kassenbon"], "Чек"),
    ]
}
