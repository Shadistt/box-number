import Foundation
import Supabase
import Observation

/// Места и вещи одного переезда. Сервер — источник правды; локальный кеш добавим следом.
@MainActor
@Observable
final class PlacesStore {
    let move: Move
    var destinations: [MoveDestination]
    var places: [Place] = []
    var items: [UUID: [Item]] = [:]          // place_id → вещи
    var loading = false
    var loaded = false
    var error: String?

    init(move: Move, destinations: [MoveDestination]) {
        self.move = move
        self.destinations = destinations.sorted { $0.position < $1.position }
    }

    func place(_ id: UUID) -> Place? { places.first { $0.id == id } }
    func items(of placeId: UUID) -> [Item] { items[placeId] ?? [] }
    func destination(_ id: UUID?) -> MoveDestination? { destinations.first { $0.id == id } }

    // MARK: загрузка

    func load() async {
        loading = true; defer { loading = false }
        do {
            places = try await supabase.from("places").select(Place.columns)
                .eq("move_id", value: move.id.uuidString).is("deleted_at", value: nil)
                .order("created_at").execute().value
            let ids = places.map(\.id.uuidString)
            if ids.isEmpty { items = [:] } else {
                let all: [Item] = try await supabase.from("items").select(Item.columns)
                    .in("place_id", values: ids).is("deleted_at", value: nil)
                    .order("position").order("created_at").execute().value
                items = Dictionary(grouping: all, by: \.placeId)
            }
            destinations = try await supabase.from("move_destinations").select()
                .eq("move_id", value: move.id.uuidString).is("deleted_at", value: nil)
                .order("position").execute().value
            loaded = true
        } catch { self.error = error.localizedDescription }
    }

    // MARK: места

    func createPlace(kind: PlaceKind, customKind: String? = nil) async throws -> Place {
        let number: String = try await supabase.rpc("next_place_number", params: ["p_move": move.id.uuidString]).execute().value
        let user = try await supabase.auth.session.user
        var row: [String: AnyJSON] = [
            "move_id": .string(move.id.uuidString), "number": .string(number),
            "kind": .string(kind.rawValue), "created_by": .string(user.id.uuidString)
        ]
        if let customKind { row["custom_kind"] = .string(customKind) }
        // Единственное направление подставляем сразу
        if destinations.count == 1 { row["destination_id"] = .string(destinations[0].id.uuidString) }
        let place: Place = try await supabase.from("places").insert(row).select(Place.columns).single().execute().value
        places.append(place)
        return place
    }

    /// Частичное обновление; поля nil не трогаем.
    func updatePlace(_ id: UUID, title: String? = nil, number: String? = nil, kind: PlaceKind? = nil,
                     customKind: String?? = nil, destinationId: UUID?? = nil, status: PlaceStatus? = nil) async throws {
        var patch: [String: AnyJSON] = [:]
        if let title { patch["title"] = .string(title) }
        if let number { patch["number"] = .string(number) }
        if let kind { patch["kind"] = .string(kind.rawValue) }
        if let customKind { patch["custom_kind"] = customKind.map { .string($0) } ?? .null }
        if let destinationId { patch["destination_id"] = destinationId.map { .string($0.uuidString) } ?? .null }
        if let status {
            patch["status"] = .string(status.rawValue)
            let now = AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
            switch status {
            case .packed: patch["packed_at"] = now; patch["unpacked_at"] = .null
            case .unpacking: patch["unpacked_at"] = now
            case .done: patch["unpacked_at"] = now
            case .open: patch["packed_at"] = .null; patch["unpacked_at"] = .null
            }
        }
        guard !patch.isEmpty else { return }
        do {
            let updated: Place = try await supabase.from("places").update(patch).eq("id", value: id.uuidString)
                .select(Place.columns).single().execute().value
            if let i = places.firstIndex(where: { $0.id == id }) { places[i] = updated }
        } catch {
            if "\(error)".contains("places_number_unique") { throw PlacesError.numberTaken }
            throw error
        }
    }

    func deletePlace(_ id: UUID) async throws {
        try await supabase.from("places").update(["deleted_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("id", value: id.uuidString).execute()
        places.removeAll { $0.id == id }
        items[id] = nil
    }

    // MARK: направления

    func addDestination(_ name: String) async throws -> MoveDestination {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if destinations.contains(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { throw PlacesError.duplicateDestination }
        if destinations.count >= AppConfig.maxDestinations { throw PlacesError.destinationsLimit }
        let d: MoveDestination = try await supabase.from("move_destinations")
            .insert(["move_id": move.id.uuidString, "name": clean, "position": String(destinations.count)])
            .select().single().execute().value
        destinations.append(d)
        return d
    }

    // MARK: вещи

    @discardableResult
    func addItem(to placeId: UUID, title: String, source: CaptionSource, id: UUID = UUID()) async throws -> Item {
        let user = try await supabase.auth.session.user
        let position = (items[placeId]?.map(\.position).max() ?? -1) + 1
        let row: [String: AnyJSON] = [
            "id": .string(id.uuidString), "place_id": .string(placeId.uuidString), "title": .string(title),
            "caption_source": .string(source.rawValue), "position": .integer(position),
            "created_by": .string(user.id.uuidString)
        ]
        let item: Item = try await supabase.from("items").insert(row).select(Item.columns).single().execute().value
        items[placeId, default: []].append(item)
        return item
    }

    func updateItem(_ id: UUID, title: String? = nil, source: CaptionSource? = nil,
                    photo: String? = nil, thumb: String? = nil, taken: Bool? = nil, placeId: UUID? = nil) async throws {
        var patch: [String: AnyJSON] = [:]
        if let title { patch["title"] = .string(title) }
        if let source { patch["caption_source"] = .string(source.rawValue) }
        if let photo { patch["photo"] = .string(photo) }
        if let thumb { patch["thumb"] = .string(thumb) }
        if let taken { patch["taken_at"] = taken ? .string(ISO8601DateFormatter().string(from: Date())) : .null }
        if let placeId { patch["place_id"] = .string(placeId.uuidString) }
        guard !patch.isEmpty else { return }
        let updated: Item = try await supabase.from("items").update(patch).eq("id", value: id.uuidString)
            .select(Item.columns).single().execute().value
        replaceItem(updated)
    }

    func deleteItem(_ id: UUID) async throws {
        try await supabase.from("items").update(["deleted_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))])
            .eq("id", value: id.uuidString).execute()
        for key in items.keys { items[key]?.removeAll { $0.id == id } }
        PhotoStore.deleteLocal(id)
    }

    private func replaceItem(_ item: Item) {
        for key in items.keys { items[key]?.removeAll { $0.id == item.id } }
        items[item.placeId, default: []].append(item)
        items[item.placeId]?.sort { ($0.position, $0.createdAt) < ($1.position, $1.createdAt) }
    }
}

enum PlacesError: LocalizedError {
    case numberTaken, duplicateDestination, destinationsLimit, needDestination
    var errorDescription: String? {
        switch self {
        case .numberTaken: "Номер занят"
        case .duplicateDestination: "Такое направление уже есть"
        case .destinationsLimit: "Не больше \(AppConfig.maxDestinations) направлений"
        case .needDestination: "Сначала выберите, куда едет"
        }
    }
}
