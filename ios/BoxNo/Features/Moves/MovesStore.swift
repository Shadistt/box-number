import Foundation
import Supabase
import Observation

/// Загрузка и создание переездов. Первый спринт — напрямую в Supabase; офлайн-кеш добавим следом.
@MainActor
@Observable
final class MovesStore {
    var moves: [Move] = []
    var destinations: [UUID: [MoveDestination]] = [:]
    var placesCount: [UUID: Int] = [:]
    /// Места из чужих переездов, к которым мне дали доступ (§8): переезд целиком не виден.
    var sharedPlaces: [Place] = []
    /// Кто ещё в переезде (вариант A, 02.11.2026): владелец и участники с активным доступом, без меня.
    var people: [UUID: [MovePerson]] = [:]
    /// Моя роль в чужих переездах: «view» / «edit».
    var myRole: [UUID: String] = [:]
    var loading = false
    var loaded = false            // был ли хоть один ответ сервера или кеш
    var error: String?

    init() { restoreCache() }

    func load() async {
        loading = true; defer { loading = false }
        do {
            moves = try await supabase.from("moves").select()
                .is("deleted_at", value: nil).order("position").order("created_at", ascending: false)
                .execute().value
            let dests: [MoveDestination] = try await supabase.from("move_destinations").select()
                .is("deleted_at", value: nil).order("position").execute().value
            destinations = Dictionary(grouping: dests, by: \.moveId)
            // Все видимые места (RLS): счётчики по переездам + общие места из чужих переездов.
            let places: [Place] = try await supabase.from("places").select(Place.columns)
                .is("deleted_at", value: nil).order("created_at").execute().value
            placesCount = Dictionary(grouping: places, by: \.moveId).mapValues(\.count)
            let mine = Set(moves.map(\.id))
            sharedPlaces = places.filter { !mine.contains($0.moveId) }
            await loadPeople()
            loaded = true
            saveCache()
        } catch { self.error = error.localizedDescription }
    }

    /// Аватарки на карточках. Ошибка тут не ломает главный экран — просто без аватарок.
    private func loadPeople() async {
        if let rows: [MovePerson] = try? await supabase.rpc("move_people").execute().value {
            people = Dictionary(grouping: rows, by: \.moveId)
        }
        struct R: Decodable { let move_id: UUID; let role: String }
        if let me = supabase.auth.currentUser?.id,
           let rows: [R] = try? await supabase.from("move_access").select("move_id,role").eq("user_id", value: me).eq("status", value: "active").execute().value {
            myRole = Dictionary(rows.map { ($0.move_id, $0.role) }, uniquingKeysWith: { a, _ in a })
        }
    }

    /// Ручной порядок карточек: позиции 0…n по текущему массиву.
    func reorder(_ ids: [UUID]) async {
        var byId = Dictionary(uniqueKeysWithValues: moves.map { ($0.id, $0) })
        for (i, id) in ids.enumerated() { byId[id]?.position = i }
        moves = ids.compactMap { byId[$0] } + moves.filter { !ids.contains($0.id) }
        saveCache()
        for (i, id) in ids.enumerated() {
            do { try await supabase.from("moves").update(["position": i]).eq("id", value: id.uuidString).execute() }
            catch { print("reorder:", error) }
        }
    }

    // MARK: кеш главного экрана — чтобы карточки были на месте сразу при запуске

    private struct Snapshot: Codable { var moves: [Move]; var destinations: [UUID: [MoveDestination]]; var placesCount: [UUID: Int]; var sharedPlaces: [Place]?; var people: [UUID: [MovePerson]]?; var myRole: [UUID: String]? }
    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("moves.json")

    private func restoreCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let snap = try? JSONDecoder.supabase.decode(Snapshot.self, from: data) else { return }
        moves = snap.moves; destinations = snap.destinations; placesCount = snap.placesCount; sharedPlaces = snap.sharedPlaces ?? []; people = snap.people ?? [:]; myRole = snap.myRole ?? [:]; loaded = true
    }

    private func saveCache() {
        let snap = Snapshot(moves: moves, destinations: destinations, placesCount: placesCount, sharedPlaces: sharedPlaces, people: people, myRole: myRole)
        if let data = try? JSONEncoder.supabase.encode(snap) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }

    static func clearCache() { try? FileManager.default.removeItem(at: cacheURL) }

    /// Удалить переезд: мягко (deleted_at) — переезд и его места исчезают из списков, фото в R2 чистятся отдельно (todo: R2 orphans).
    /// Статическая: вызывается с экрана мест; главный перезагружает список при возврате (onAppear → load).
    static func deleteMove(_ id: UUID) async throws {
        let now = Date()
        try await supabase.from("places").update(["deleted_at": now]).eq("move_id", value: id).execute()
        try await supabase.from("moves").update(["deleted_at": now]).eq("id", value: id).execute()
        clearCache()
    }

    func createMove(from: String, to: [String]) async throws -> Move {
        let user = try await supabase.auth.session.user
        let move: Move = try await supabase.from("moves")
            .insert(["owner_id": user.id.uuidString, "from_city": from])
            .select().single().execute().value
        let rows = to.enumerated().map { ["move_id": move.id.uuidString, "name": $1, "position": String($0)] }
        try await supabase.from("move_destinations").insert(rows).execute()
        await load()
        return move
    }
}

/// Участник переезда для аватарки на карточке (RPC move_people).
struct MovePerson: Codable, Hashable {
    var moveId: UUID
    var userId: UUID
    var role: String
    var isOwner: Bool
    var firstName: String
    var lastName: String
    var email: String?
    var avatar: String
    var photo: String?
    enum CodingKeys: String, CodingKey { case role, email, avatar, photo
        case moveId = "move_id", userId = "user_id", isOwner = "is_owner", firstName = "first_name", lastName = "last_name" }
    var person: Person { Person(id: userId, firstName: firstName, lastName: lastName, email: email, avatar: avatar, photo: photo) }
}
