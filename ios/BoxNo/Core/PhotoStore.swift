import UIKit
import Supabase

/// Фото вещей: сжатие на устройстве (1 600 px + превью 320 px), локальные файлы,
/// загрузка в R2 по подписанному URL из Edge Function, показ по подписанной ссылке.
enum PhotoStore {
    private static let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()
    private static let cache = NSCache<NSString, UIImage>()

    /// Счётчик замен фото: превью в сетке держат картинку в @State и перезагружаются по изменению `version`
    /// (id вещи при «Переснять»/«Обрезать» не меняется, и без этого плитка показывала старое фото).
    @MainActor @Observable final class Changes { static let shared = Changes(); var version = 0 }

    static func localURL(_ id: UUID, thumb: Bool) -> URL {
        dir.appendingPathComponent(id.uuidString + (thumb ? "_t.jpg" : ".jpg"))
    }

    /// Сжимает и сохраняет обе версии. Оригинал не хранится.
    @discardableResult
    static func save(_ image: UIImage, for id: UUID) -> (photo: Data, thumb: Data)? {
        guard let photo = image.resized(maxSide: 1600).jpegData(compressionQuality: 0.82),
              let thumb = image.resized(maxSide: 320).jpegData(compressionQuality: 0.7) else { return nil }
        try? photo.write(to: localURL(id, thumb: false), options: .atomic)
        try? thumb.write(to: localURL(id, thumb: true), options: .atomic)
        cache.removeObject(forKey: id.uuidString as NSString)
        cache.removeObject(forKey: (id.uuidString + "_t") as NSString)
        Task { @MainActor in Changes.shared.version += 1 }
        return (photo, thumb)
    }

    static func deleteLocal(_ id: UUID) {
        try? FileManager.default.removeItem(at: localURL(id, thumb: false))
        try? FileManager.default.removeItem(at: localURL(id, thumb: true))
    }

    /// Локальный файл → иначе качаем по подписанной ссылке и кладём рядом.
    static func image(for item: Item, thumb: Bool) async -> UIImage? {
        await image(localId: item.id, remoteKey: thumb ? item.thumb : item.photo, thumb: thumb)
    }

    /// Фото самого места (коробки): ключ places/<id>/photo.jpg в places.number_photo, превью — рядом.
    static func image(forPlace place: Place, thumb: Bool) async -> UIImage? {
        let key = place.numberPhoto.map { thumb ? $0.replacingOccurrences(of: "/photo.jpg", with: "/thumb.jpg") : $0 }
        return await image(localId: place.id, remoteKey: key, thumb: thumb)
    }

    static func image(localId id: UUID, remoteKey: String?, thumb: Bool) async -> UIImage? {
        let key = (id.uuidString + (thumb ? "_t" : "")) as NSString
        if let img = cache.object(forKey: key) { return img }
        let url = localURL(id, thumb: thumb)
        if let img = UIImage(contentsOfFile: url.path) { cache.setObject(img, forKey: key); return img }
        guard let remoteKey else { return nil }
        do {
            let ticket: ViewTicket = try await supabase.functions.invoke("photo-view-url", options: .init(body: ["key": remoteKey]))
            let (data, _) = try await URLSession.shared.data(from: URL(string: ticket.url)!)
            try? data.write(to: url, options: .atomic)
            if let img = UIImage(data: data) { cache.setObject(img, forKey: key); return img }
        } catch { print("photo-view-url:", error) }
        return nil
    }

    /// Загрузка в R2. Если не вышло (нет сети, функция не настроена) — фото остаётся локально, повторим позже.
    static func upload(_ id: UUID, photo: Data, thumb: Data, store: PlacesStore) async {
        do {
            let t: UploadTicket = try await supabase.functions.invoke("photo-upload-url", options: .init(body: ["item_id": id.uuidString]))
            try await put(t.photoUrl, photo)
            try await put(t.thumbUrl, thumb)
            try await store.updateItem(id, photo: t.photoKey, thumb: t.thumbKey)
        } catch { print("upload:", error) }
    }

    /// Фото места: тот же тикет, но по place_id; ключ сохраняем в places.number_photo.
    static func uploadPlacePhoto(_ placeId: UUID, photo: Data, thumb: Data, store: PlacesStore) async {
        do {
            let t: UploadTicket = try await supabase.functions.invoke("photo-upload-url", options: .init(body: ["place_id": placeId.uuidString]))
            try await put(t.photoUrl, photo)
            try await put(t.thumbUrl, thumb)
            try await store.updatePlace(placeId, numberPhoto: .some(t.photoKey))
        } catch { print("place photo upload:", error) }
    }

    private static func put(_ url: String, _ data: Data) async throws {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "PUT"
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (_, resp) = try await URLSession.shared.upload(for: req, from: data)
        guard (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) == true else {
            throw URLError(.badServerResponse)
        }
    }

    struct UploadTicket: Decodable {
        let photoKey: String, photoUrl: String, thumbKey: String, thumbUrl: String
        enum CodingKeys: String, CodingKey { case photoKey = "photo_key", photoUrl = "photo_url", thumbKey = "thumb_key", thumbUrl = "thumb_url" }
    }
    struct ViewTicket: Decodable { let url: String }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        if scale >= 1 && imageOrientation == .up { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
