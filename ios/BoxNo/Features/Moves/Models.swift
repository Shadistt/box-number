import Foundation

/// Модели под таблицы Supabase (миграция 0001). Имена полей — как в базе.
struct Move: Codable, Identifiable, Hashable {
    var id: UUID
    var ownerId: UUID
    var title: String?
    var fromCity: String
    var status: String
    var nextNumber: Int
    var position: Int = 0
    var createdAt: Date
    /// Для мест из чужих переездов (доступ только к месту): переезд целиком нам не виден.
    static func placeholder(id: UUID) -> Move { Move(id: id, ownerId: id, title: "Общее место", fromCity: "", status: "active", nextNumber: 1, createdAt: Date()) }
    enum CodingKeys: String, CodingKey { case id, title, status, position
        case ownerId = "owner_id", fromCity = "from_city", nextNumber = "next_number", createdAt = "created_at" }
}

struct MoveDestination: Codable, Identifiable, Hashable {
    var id: UUID
    var moveId: UUID
    var name: String
    var position: Int
    enum CodingKeys: String, CodingKey { case id, name, position, moveId = "move_id" }
}

enum PlaceStatus: String, Codable { case open, packed, unpacking, done }

struct Place: Codable, Identifiable, Hashable {
    var id: UUID
    var moveId: UUID
    var number: String
    var title: String
    var kind: PlaceKind
    var customKind: String?
    var destinationId: UUID?
    var status: PlaceStatus
    var packedAt: Date?
    var unpackedAt: Date?
    var numberPhoto: String?
    var shared: Bool
    var createdAt: Date
    enum CodingKeys: String, CodingKey { case id, number, title, kind, status, shared
        case moveId = "move_id", customKind = "custom_kind", destinationId = "destination_id"
        case packedAt = "packed_at", unpackedAt = "unpacked_at", numberPhoto = "number_photo", createdAt = "created_at" }

    static let columns = "id,move_id,number,title,kind,custom_kind,destination_id,status,packed_at,unpacked_at,number_photo,shared,created_at"

    /// «Коробка № 19», «Свой вариант: Велосипед»
    var kindTitle: String { kind == .custom ? (customKind ?? "Свой вариант") : kind.title }
    var displayTitle: String { title.isEmpty ? "\(kind.title) без названия" : title }
}

enum CaptionSource: String, Codable { case ai, user }

struct Item: Codable, Identifiable, Hashable {
    var id: UUID
    var placeId: UUID
    var title: String
    var captionSource: CaptionSource
    var photo: String?
    var thumb: String?
    var takenAt: Date?
    var position: Int
    var createdAt: Date
    enum CodingKeys: String, CodingKey { case id, title, photo, thumb, position
        case placeId = "place_id", captionSource = "caption_source", takenAt = "taken_at", createdAt = "created_at" }

    static let columns = "id,place_id,title,caption_source,photo,thumb,taken_at,position,created_at"
    var isTaken: Bool { takenAt != nil }
}

extension Move {
    func displayTitle(destinations: [MoveDestination]) -> String {
        if let t = title, !t.isEmpty { return t }
        let first = destinations.sorted { $0.position < $1.position }.first?.name ?? ""
        let more = destinations.count > 1 ? " +\(destinations.count - 1)" : ""
        return (fromCity.isEmpty ? first : "\(fromCity) → \(first)") + more
    }
}

/// Склонение «1 вещь / 2 вещи / 5 вещей», «мест».
enum Plural {
    static func things(_ n: Int) -> String { "\(n) " + form(n, "вещь", "вещи", "вещей") }
    static func places(_ n: Int) -> String { "\(n) " + form(n, "место", "места", "мест") }
    static func form(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10, m100 = n % 100
        if m10 == 1 && m100 != 11 { return one }
        if (2...4).contains(m10) && !(12...14).contains(m100) { return few }
        return many
    }
}
