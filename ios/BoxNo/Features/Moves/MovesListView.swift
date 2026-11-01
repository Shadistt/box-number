import SwiftUI
import Supabase

struct MovesListView: View {
    let startEmpty: Bool
    @State private var store = MovesStore()
    @State private var showNew = false
    @State private var created: Move? = nil
    @State private var declined: AccessStore.Invitation? = nil   // после «Отклонить» — предложить заблокировать
    @Environment(\.scenePhase) private var scenePhase
    @State private var openMove: Move? = nil
    @State private var openShared: Place? = nil
    // Зажать карточку → поднимается, тянем вверх/вниз, соседи раздвигаются (тот же паттерн, что направления).
    @State private var dragging: UUID? = nil
    @State private var dragOffset: CGFloat = 0
    @State private var dropIndex: Int? = nil
    @State private var frames: [UUID: CGRect] = [:]     // рамки карточек в .global — найти карточку под пальцем и высоты для раздвигания
    @State private var dragStartY: CGFloat = 0
    @State private var justDropped = false              // отпустили после переноса — тап кнопки по этому же касанию не считаем
    private let spacing: CGFloat = 10

    private var active: [Move] { store.moves.filter { $0.status == "active" } }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    InvitationsSection(onChanged: { await store.load() }, onDeclined: { inv in withAnimation(.snappy) { declined = inv } })
                    if store.moves.isEmpty && store.sharedPlaces.isEmpty && store.loaded && !store.loading && AccessStore.shared.invitations.isEmpty {
                        EmptyMovesView()
                    } else {
                        Text("СЕЙЧАС").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
                        ForEach(Array(active.enumerated()), id: \.element.id) { i, m in
                            let lifted = dragging == m.id
                            // Тап — настоящая кнопка; «зажать и тянуть» — UIKit-распознаватель на ScrollView (ListLongPress ниже),
                            // без SwiftUI-жестов на карточке: они ломали прокрутку или тап (релизы 41–43).
                            Button { if dragging == nil && !justDropped { openMove = m } } label: {
                                MoveCard(move: m, destinations: store.destinations[m.id] ?? [], places: store.placesCount[m.id] ?? 0)
                            }
                                .buttonStyle(.plain)
                                .background(GeometryReader { g in Color.clear.preference(key: CardFrameKey.self, value: [m.id: g.frame(in: .global)]) })
                                .scaleEffect(lifted ? 1.03 : 1)
                                .shadow(color: .black.opacity(lifted ? 0.22 : 0), radius: lifted ? 16 : 0, y: lifted ? 8 : 0)
                                .offset(y: lifted ? dragOffset : shift(i))
                                .zIndex(lifted ? 1 : 0)
                        }
                        if !store.sharedPlaces.isEmpty {
                            Text("ОБЩИЕ МЕСТА").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 12)
                            ForEach(store.sharedPlaces) { p in
                                Button { openShared = p } label: {
                                    HStack(spacing: 12) {
                                        BoxTileView(place: p, size: 56)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("\(p.kind.numberLabel) № \(p.number) · \(p.displayTitle)").font(.system(size: 16, weight: .bold)).lineLimit(1)
                                            Text("Общее · вам открыли доступ").font(.footnote).foregroundStyle(Theme.muted)
                                        }
                                        Spacer(); Chevron()
                                    }
                                    .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 18)).contentShape(RoundedRectangle(cornerRadius: 18))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)           // отступ внутри ScrollView: тень и увеличение поднятой карточки не обрезаются краем
                .padding(.bottom, 110)
                .background(ListLongPress(began: liftCard, moved: moveCard, ended: dropCard, cancelled: cancelDrag))
                .onPreferenceChange(CardFrameKey.self) { new in
                    // Во время перетаскивания рамки едут вместе с карточками — порядок и высоты берём из снимка до подъёма.
                    if dragging == nil { frames = new }
                }
            }
            .scrollIndicators(.hidden)             // полоса прокрутки не нужна — карточки и так читаются
            .scrollDisabled(dragging != nil)
            FAB(title: "Новый переезд") { showNew = true }
            .padding(.bottom, 20)
        }
        .overlay { BlockAfterDeclineOverlay(invitation: $declined) }
        .navigationDestination(item: $openMove) { m in PlacesView(move: m, destinations: store.destinations[m.id] ?? []) }
        .navigationDestination(item: $openShared) { p in PlaceView(store: PlacesStore(move: .placeholder(id: p.moveId), destinations: []), placeId: p.id) }
        .task { await store.load(); await AccessStore.shared.loadInvitations() }
        // Живые обновления: дали доступ, добавили в семью, изменился чужой переезд → список сам обновится.
        .task(id: supabase.auth.currentUser?.id) {
            guard let uid = supabase.auth.currentUser?.id else { return }
            await LiveUpdates.watchHome(userId: uid) { await store.load(); await AccessStore.shared.loadInvitations() }
        }
        .onAppear { Task { await store.load() } }
        // Вернулись в приложение — обновить список: доступ к чужому переезду мог появиться, пока нас не было.
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await store.load(); await AccessStore.shared.loadInvitations() } } }
        .refreshable { await store.load(); await AccessStore.shared.loadInvitations() }
        // Новый переезд открываем сразу (после закрытия листа — иначе push и dismiss спорят).
        .sheet(isPresented: $showNew, onDismiss: { if let m = created { created = nil; openMove = m } }) {
            NewMoveView(store: store, onCreated: { created = $0 })
        }
    }

    private func height(_ m: Move) -> CGFloat { frames[m.id]?.height ?? 100 }

    // MARK: перетаскивание (точки — в координатах окна)

    /// Палец удержали 0,35 с: поднимаем карточку под ним. Массив не меняется до отпускания.
    private func liftCard(at p: CGPoint) {
        guard dragging == nil, let m = active.first(where: { frames[$0.id]?.contains(p) == true }) else { return }
        dragStartY = p.y; dragOffset = 0; dropIndex = nil
        withAnimation(.snappy(duration: 0.2)) { dragging = m.id }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func moveCard(to p: CGPoint) {
        guard let dragging, let start = active.firstIndex(where: { $0.id == dragging }) else { return }
        dragOffset = p.y - dragStartY
        let target = targetIndex(from: start, translation: dragOffset)
        if target != dropIndex {
            withAnimation(.snappy(duration: 0.25)) { dropIndex = target }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func dropCard(at p: CGPoint) {
        guard let dragging, let start = active.firstIndex(where: { $0.id == dragging }) else { return }
        let target = dropIndex ?? start
        var ids = active.map(\.id)
        let moved = ids.remove(at: start); ids.insert(moved, at: target)
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            // визуально карточка остаётся под пальцем: компенсируем смену позиции в массиве
            let delta = topOffset(of: target, in: ids) - topOffset(of: start, in: active.map(\.id))
            dragOffset = p.y - dragStartY - delta
            dropIndex = nil
            if target != start { Task { await store.reorder(ids) } }
        }
        withAnimation(.snappy(duration: 0.25)) { dragOffset = 0; self.dragging = nil }
        justDropped = true
        Task { try? await Task.sleep(for: .seconds(0.4)); justDropped = false }
    }

    private func cancelDrag() {
        guard dragging != nil else { return }
        withAnimation(.snappy(duration: 0.25)) { dragOffset = 0; dropIndex = nil; dragging = nil }
    }

    /// Верх карточки с данным индексом в заданном порядке (сумма высот + отступы).
    private func topOffset(of index: Int, in ids: [UUID]) -> CGFloat {
        ids.prefix(index).reduce(0) { $0 + (frames[$1]?.height ?? 100) + spacing }
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

struct CardFrameKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
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
            Text("\(places.placesWord) · с \(move.createdAt.formatted(.dateTime.day().month(.wide)))")
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
