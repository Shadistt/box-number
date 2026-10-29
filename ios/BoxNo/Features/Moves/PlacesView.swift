import SwiftUI

/// Места переезда — первый спринт: список и заглушка добавления.
struct PlacesView: View {
    let move: Move
    let destinations: [MoveDestination]
    @State private var places: [Place] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Переезд из \(move.fromCity.isEmpty ? "…" : move.fromCity)").font(.system(size: 20, weight: .heavy))
                Text("в " + destinations.map(\.name).joined(separator: ", ") + " · \(places.count) мест").font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(places) { p in
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0xE3E1DA)).aspectRatio(1, contentMode: .fit)
                                .overlay(Text(p.number).font(.system(size: 44, weight: .heavy)))
                            Text(p.title.isEmpty ? "Коробка без названия" : p.title).font(.headline)
                        }
                        .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 22))
                    }
                }
                .padding(.bottom, 100)
            }
        }
        .padding(.horizontal, 16).background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            places = (try? await supabase.from("places").select("id,move_id,number,title,kind,destination_id,status")
                .eq("move_id", value: move.id.uuidString).is("deleted_at", value: nil).execute().value) ?? []
        }
    }
}
