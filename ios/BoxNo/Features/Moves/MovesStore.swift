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
            // Только move_id: полный Place здесь не нужен, а неполный набор колонок ломал декодирование → счётчики «0 мест».
            struct Row: Decodable { let moveId: UUID; enum CodingKeys: String, CodingKey { case moveId = "move_id" } }
            let places: [Row] = try await supabase.from("places").select("move_id")
                .is("deleted_at", value: nil).execute().value
            placesCount = Dictionary(grouping: places, by: \.moveId).mapValues(\.count)
            loaded = true
            saveCache()
        } catch { self.error = error.localizedDescription }
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

    private struct Snapshot: Codable { var moves: [Move]; var destinations: [UUID: [MoveDestination]]; var placesCount: [UUID: Int] }
    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("moves.json")

    private func restoreCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let snap = try? JSONDecoder.supabase.decode(Snapshot.self, from: data) else { return }
        moves = snap.moves; destinations = snap.destinations; placesCount = snap.placesCount; loaded = true
    }

    private func saveCache() {
        let snap = Snapshot(moves: moves, destinations: destinations, placesCount: placesCount)
        if let data = try? JSONEncoder.supabase.encode(snap) { try? data.write(to: Self.cacheURL, options: .atomic) }
    }

    static func clearCache() { try? FileManager.default.removeItem(at: cacheURL) }

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
