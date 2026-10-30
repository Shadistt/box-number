import SwiftUI

/// Экран «Места» переезда (ТЗ §5): шапка, поиск, Места / Все вещи, фильтры по типу, сетка плиток, FAB.
struct PlacesView: View {
    @State private var store: PlacesStore
    @State private var query = ""
    @State private var tab: Tab = .places
    @State private var filter: PlaceKind? = nil
    @State private var showTypePicker = false
    @State private var open: PlaceRef? = nil
    @State private var creating = false

    enum Tab: String, CaseIterable { case places = "Места", items = "Все вещи" }
    struct PlaceRef: Identifiable, Hashable { let id: UUID }

    init(move: Move, destinations: [MoveDestination]) {
        _store = State(initialValue: PlacesStore(move: move, destinations: destinations))
    }

    private var filtered: [Place] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.places.filter { p in
            (filter == nil || p.kind == filter) &&
            (q.isEmpty || p.title.lowercased().contains(q) || p.number.lowercased().contains(q)
             || store.items(of: p.id).contains { $0.title.lowercased().contains(q) })
        }
    }
    private var kindsPresent: [PlaceKind] { PlaceKind.allCases.filter { k in store.places.contains { $0.kind == k } } }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                header
                SearchField(text: $query, placeholder: "Найти вещь или место")
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue) }
                }.pickerStyle(.segmented)
                if kindsPresent.count > 1 { filters }
                ScrollView {
                    if tab == .places { grid } else { allItems }
                    Color.clear.frame(height: 110)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.load() }
            }
            .padding(.horizontal, 16)

            FAB(title: "Добавить место") { showTypePicker = true }
                .padding(.bottom, 20)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.load() }
        .onAppear { if store.loaded { Task { await store.load() } } }
        .sheet(isPresented: $showTypePicker) {
            TypePickerView { kind, custom in Task { await create(kind, custom) } }
        }
        .navigationDestination(item: $open) { ref in PlaceView(store: store, placeId: ref.id) }
        .overlay { if creating { ProgressView().controlSize(.large) } }
        .alert("Не получилось", isPresented: .init(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Ок") {}
        } message: { Text(store.error ?? "") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Переезд из \(store.move.fromCity.isEmpty ? "…" : store.move.fromCity)")
                .font(.system(size: 22, weight: .heavy))
            Text("в " + store.destinations.map(\.name).joinedRussian() + " · " + Plural.places(store.places.count))
                .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
        }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Chip(title: "Все", selected: filter == nil) { filter = nil }
                ForEach(kindsPresent) { k in Chip(title: k.short, selected: filter == k) { filter = k } }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize, axes: [.horizontal, .vertical])
        .padding(.horizontal, -16).frame(height: 36)
    }

    @ViewBuilder
    private var grid: some View {
        if store.places.isEmpty && store.loaded && !store.loading {
            VStack(spacing: 8) {
                Image(systemName: "shippingbox").font(.system(size: 40)).foregroundStyle(Theme.muted)
                Text("Мест пока нет").font(.headline)
                Text("Добавьте первую коробку — номер напишите на ней маркером.")
                    .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity).padding(.top, 60)
        } else {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top), GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
            ForEach(filtered) { p in
                Button { open = PlaceRef(id: p.id) } label: {
                    PlaceTile(place: p, count: store.items(of: p.id).count, destination: store.destination(p.destinationId)?.name)
                }.buttonStyle(.plain)
            }
        }
        }
    }

    private var allItems: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(filtered) { p in
                let its = store.items(of: p.id)
                VStack(alignment: .leading, spacing: 8) {
                    Button { open = PlaceRef(id: p.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: p.kind.symbol).font(.system(size: 18, weight: .semibold))
                            Text("№ \(p.number) · \(p.displayTitle)").font(.system(size: 16, weight: .bold)).lineLimit(1)
                            Spacer()
                            Text(Plural.things(its.count)).font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }.buttonStyle(.plain)
                    if its.isEmpty {
                        Text("Пока пусто").font(.footnote).foregroundStyle(Theme.muted).padding(.leading, 28)
                    } else {
                        ForEach(its) { it in
                            HStack(spacing: 10) {
                                ItemThumb(item: it, size: 36)
                                Text(it.title).font(.subheadline).strikethrough(it.isTaken).foregroundStyle(it.isTaken ? Theme.muted : Theme.ink)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func create(_ kind: PlaceKind, _ custom: String?) async {
        creating = true; defer { creating = false }
        do {
            let p = try await store.createPlace(kind: kind, customKind: custom)
            open = PlaceRef(id: p.id)
        } catch { store.error = error.localizedDescription }
    }
}

// MARK: - детали

struct PlaceTile: View {
    let place: Place
    let count: Int
    let destination: String?

    private var tileStatus: String {
        switch place.status {
        case .open: return "\(place.kindTitle) · \(Plural.things(count))"
        case .packed: return "Запакована · \(Plural.things(count))"
        case .unpacking: return "Распаковка · \(Plural.things(count))"
        case .done: return "Разобрана"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 16).fill(place.status == .packed ? Theme.ink : Color(hex: 0xE8E6E0))
                    .aspectRatio(1, contentMode: .fit)
                VStack {
                    Image(systemName: place.kind.symbol).font(.system(size: 26, weight: .medium))
                    Text(place.number).font(.system(size: 40, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(place.status == .packed ? .white : Theme.ink)
                .frame(maxHeight: .infinity)
                HStack {
                    if place.status == .packed {
                        Image(systemName: "lock.fill").font(.caption.weight(.bold)).padding(6)
                            .background(Theme.accent, in: Circle()).foregroundStyle(Theme.ink)
                    } else if place.status == .done {
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).padding(6)
                            .background(Theme.ink, in: Circle()).foregroundStyle(.white)
                    }
                    Spacer()
                    if let destination {
                        Text(destination).font(.caption2.weight(.bold)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.white, in: Capsule()).foregroundStyle(Theme.ink)
                            .frame(maxWidth: 110, alignment: .trailing)
                    }
                }.padding(8)
            }
            Text(place.displayTitle).font(.system(size: 15, weight: .bold)).lineLimit(1)
            Text(tileStatus).font(.caption.weight(place.status == .open ? .regular : .semibold))
                .foregroundStyle(place.status == .packed ? Theme.accent : Theme.muted).lineLimit(1)
        }
        .padding(8).background(Theme.card, in: RoundedRectangle(cornerRadius: 22))
        .opacity(place.status == .done ? 0.55 : 1)
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 14).frame(height: 36)
                .background(selected ? Theme.ink : Theme.card, in: Capsule())
                .foregroundStyle(selected ? .white : Theme.ink)
        }.buttonStyle(.plain)
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text).autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
            }
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct FAB: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "plus").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 36, height: 36).background(Theme.accent, in: Circle())
                Text(title).font(.system(size: 17, weight: .semibold))
            }
            .padding(.leading, 12).padding(.trailing, 26).frame(height: 58)
            .background(Theme.ink, in: Capsule()).foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
    }
}

extension Array where Element == String {
    /// «Мадрид», «Мадрид и Киев», «Мадрид, Киев и Цюрих»
    func joinedRussian() -> String {
        switch count {
        case 0: return "…"
        case 1: return self[0]
        default: return dropLast().joined(separator: ", ") + " и " + last!
        }
    }
}
