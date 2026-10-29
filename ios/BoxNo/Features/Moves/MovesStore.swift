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
    var error: String?

    func load() async {
        loading = true; defer { loading = false }
        do {
            moves = try await supabase.from("moves").select()
                .is("deleted_at", value: nil).order("created_at", ascending: false)
                .execute().value
            let dests: [MoveDestination] = try await supabase.from("move_destinations").select()
                .is("deleted_at", value: nil).order("position").execute().value
            destinations = Dictionary(grouping: dests, by: \.moveId)
            let places: [Place] = try await supabase.from("places").select("id,move_id,number,title,kind,destination_id,status")
                .is("deleted_at", value: nil).execute().value
            placesCount = Dictionary(grouping: places, by: \.moveId).mapValues(\.count)
        } catch { self.error = error.localizedDescription }
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
