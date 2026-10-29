import Foundation

/// Модели под таблицы Supabase (миграция 0001). Имена полей — как в базе.
struct Move: Codable, Identifiable, Hashable {
    var id: UUID
    var ownerId: UUID
    var title: String?
    var fromCity: String
    var status: String
    var nextNumber: Int
    var createdAt: Date
    enum CodingKeys: String, CodingKey { case id, title, status
        case ownerId = "owner_id", fromCity = "from_city", nextNumber = "next_number", createdAt = "created_at" }
}

struct MoveDestination: Codable, Identifiable, Hashable {
    var id: UUID
    var moveId: UUID
    var name: String
    var position: Int
    enum CodingKeys: String, CodingKey { case id, name, position, moveId = "move_id" }
}

struct Place: Codable, Identifiable, Hashable {
    var id: UUID
    var moveId: UUID
    var number: String
    var title: String
    var kind: String
    var destinationId: UUID?
    var status: String
    enum CodingKeys: String, CodingKey { case id, number, title, kind, status
        case moveId = "move_id", destinationId = "destination_id" }
}

extension Move {
    func displayTitle(destinations: [MoveDestination]) -> String {
        if let t = title, !t.isEmpty { return t }
        let first = destinations.sorted { $0.position < $1.position }.first?.name ?? ""
        return fromCity.isEmpty ? first : "\(fromCity) → \(first)"
    }
}
