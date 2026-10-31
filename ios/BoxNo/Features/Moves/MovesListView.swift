import SwiftUI

struct MovesListView: View {
    let startEmpty: Bool
    @State private var store = MovesStore()
    @State private var showNew = false
    @State private var openMove: Move? = nil
    // Зажать карточку → поднимается, тянем вверх/вниз, соседи раздвигаются (тот же паттерн, что направления).
    @State private var dragging: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var dropIndex: Int? = nil
    @State private var heights: [UUID: CGFloat] = [:]
    private let spacing: CGFloat = 10

    private var active: [Move] { store.moves.filter { $0.status == "active" } }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    if store.moves.isEmpty && store.loaded && !store.loading {
                        EmptyMovesView()
                    } else {
                        Text("СЕЙЧАС").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
                        ForEach(Array(active.enumerated()), id: \.element.id) { i, m in
                            let lifted = dragging == m.id
                            MoveCard(move: m, destinations: store.destinations[m.id] ?? [], places: store.placesCount[m.id] ?? 0)
                                .background(GeometryReader { g in Color.clear.preference(key: CardHeightKey.self, value: [m.id: g.size.height]) })
                                .scaleEffect(lifted ? 1.03 : 1)
                                .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: lifted ? 16 : 0, y: lifted ? 8 : 0)
                                .offset(y: lifted ? dragOffset : shift(i))
                                .zIndex(lifted ? 1 : 0)
                                .contentShape(Rectangle())
                                .onTapGesture { if dragging == nil { openMove = m } }
                                .gesture(reorderGesture(m.id, index: i))
                        }
                    }
                }
                .padding(.bottom, 110)
                .onPreferenceChange(CardHeightKey.self) { heights.merge($0) { $1 } }
            }
            .scrollIndicators(.hidden)             // полоса прокрутки не нужна — карточки и так читаются
            .scrollDisabled(dragging != nil)
            FAB(title: "Новый переезд") { showNew = true }
            .padding(.bottom, 20)
        }
        .navigationDestination(item: $openMove) { m in PlacesView(move: m, destinations: store.destinations[m.id] ?? []) }
        .task { await store.load() }
        .onAppear { Task { await store.load() } }
        .refreshable { await store.load() }
        .sheet(isPresented: $showNew) { NewMoveView(store: store) }
    }

    private func height(_ m: Move) -> CGFloat { heights[m.id] ?? 100 }

    /// Долгое нажатие (0.35 с) → перетаскивание. Массив не меняется до отпускания.
    private func reorderGesture(_ id: UUID, index start: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                switch value {
                case .first(true):
                    if dragging == nil {
                        withAnimation(.snappy(duration: 0.2)) { dragging = id }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                case .second(true, let drag?):
                    dragOffset = drag.translation.height
                    let target = targetIndex(from: start, translation: drag.translation.height)
                    if target != dropIndex {
                        withAnimation(.snappy(duration: 0.25)) { dropIndex = target }
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                default: break
                }
            }
            .onEnded { value in
                let translation: CGFloat = { if case .second(true, let d?) = value { return d.translation.height } else { return 0 } }()
                let target = dropIndex ?? start
                var ids = active.map(\.id)
                let moved = ids.remove(at: start); ids.insert(moved, at: target)
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) {
                    // визуально карточка остаётся под пальцем: компенсируем смену позиции в массиве
                    let delta = topOffset(of: target, in: ids) - topOffset(of: start, in: active.map(\.id))
                    dragOffset = translation - delta
                    dropIndex = nil
                    if target != start { Task { await store.reorder(ids) } }
                }
                withAnimation(.snappy(duration: 0.25)) { dragOffset = 0; dragging = nil }
            }
    }

    /// Верх карточки с данным индексом в заданном порядке (сумма высот + отступы).
    private func topOffset(of index: Int, in ids: [UUID]) -> CGFloat {
        ids.prefix(index).reduce(0) { $0 + (heights[$1] ?? 100) + spacing }
    }

    /// Куда «упадёт» поднятая карточка: ищем индекс по центру карточки относительно соседей.
    private func targetIndex(from start: Int, translation: CGFloat) -> Int {
        let list = active
        let center = topOffset(of: start, in: list.map(\.id)) + height(list[start]) / 2 + translation
        var y: CGFloat = 0
        for (i, m) in list.enumerated() where i != start {
            let h = height(m)
            if center < y + h / 2 { return i < start ? i : i - 1 }
            y += h + spacing
        }
        return list.count - 1
    }

    /// Сдвиг соседа на высоту поднятой карточки, пока она «проходит» его.
    private func shift(_ index: Int) -> CGFloat {
        guard let dragging, let start = active.firstIndex(where: { $0.id == dragging }), let target = dropIndex, index != start else { return 0 }
        let h = height(active[start]) + spacing
        if start < index && index <= target { return -h }
        if target <= index && index < start { return h }
        return 0
    }
}

struct CardHeightKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) { value.merge(nextValue()) { $1 } }
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
        .background(Theme.dark, in: RoundedRectangle(cornerRadius: 18))
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
