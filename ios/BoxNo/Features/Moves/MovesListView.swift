import SwiftUI

struct MovesListView: View {
    let startEmpty: Bool
    @State private var store = MovesStore()
    @State private var showNew = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.moves.isEmpty && store.loaded && !store.loading {
                        EmptyMovesView()
                    } else {
                        Text("СЕЙЧАС").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
                        ForEach(store.moves.filter { $0.status == "active" }) { m in
                            NavigationLink { PlacesView(move: m, destinations: store.destinations[m.id] ?? []) } label: {
                                MoveCard(move: m, destinations: store.destinations[m.id] ?? [], places: store.placesCount[m.id] ?? 0)
                            }
                        }
                    }
                }
                .padding(.bottom, 110)
            }
            FAB(title: "Новый переезд") { showNew = true }
            .padding(.bottom, 20)
        }
        .task { await store.load() }
        .onAppear { Task { await store.load() } }
        .refreshable { await store.load() }
        .sheet(isPresented: $showNew) { NewMoveView(store: store) }
    }
}

struct MoveCard: View {
    let move: Move
    let destinations: [MoveDestination]
    let places: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(move.displayTitle(destinations: destinations)).font(.system(size: 20, weight: .heavy))
                Text("идёт").font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(Theme.ink)
                Spacer()
            }
            Text("\(places) мест · с \(move.createdAt.formatted(.dateTime.day().month(.wide)))")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            if !destinations.isEmpty {
                // Больше трёх направлений не влезает — показываем первые и «+N».
                HStack(spacing: 6) {
                    ForEach(destinations.prefix(3)) { d in
                        Label(d.name, systemImage: "mappin").font(.caption.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.12), in: Capsule())
                            .layoutPriority(1)
                    }
                    if destinations.count > 3 {
                        Text("+\(destinations.count - 3)").font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.12), in: Capsule())
                            .layoutPriority(2)
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.white)
    }
}

struct EmptyMovesView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "shippingbox").font(.system(size: 44)).foregroundStyle(Theme.muted)
            Text("Пока пусто").font(.title3.weight(.bold))
            Text("Начните переезд — коробки получат номера, а вещи — фото и подписи.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }
}
