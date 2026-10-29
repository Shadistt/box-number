import SwiftUI

/// Экран места (ТЗ §7): плитка-иконка, название, плашка статуса (B), Фото / Список, живая камера, вещи, меню «…».
struct PlaceView: View {
    let store: PlacesStore
    let placeId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var barExpanded = false
    @State private var mode: Mode = .photos
    @State private var showCamera = false
    @State private var showDest = false
    @State private var showEdit = false
    @State private var showShare = false
    @State private var confirmDelete = false
    @State private var openItem: Item? = nil
    @State private var toast: String? = nil
    @State private var shakes: CGFloat = 0
    @FocusState private var titleFocused: Bool

    enum Mode: String, CaseIterable { case photos = "Фото", list = "Список" }

    private var place: Place? { store.place(placeId) }
    private var items: [Item] { store.items(of: placeId) }

    var body: some View {
        Group {
            if let place { content(place) } else { ProgressView() }
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                Menu {
                    Button { showEdit = true } label: { Label("Изменить место", systemImage: "pencil") }
                    Button { showDest = true } label: { Label("Куда едет", systemImage: "mappin.and.ellipse") }
                    Button {} label: { Label("Отправить как посылку", systemImage: "paperplane") }.disabled(true)
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить место", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { title = place?.title ?? "" }
        .onChange(of: place?.destinationId) { _, new in if new != nil { barExpanded = false } }
        .onChange(of: showCamera) { _, on in if !on { CameraModel.shared.start() } }
        .fullScreenCover(isPresented: $showCamera) { CameraView(store: store, placeId: placeId) }
        .sheet(isPresented: $showDest) { DestinationPickerView(store: store, placeId: placeId) }
        .sheet(isPresented: $showEdit) { EditPlaceView(store: store, placeId: placeId) }
        .sheet(item: $openItem) { ItemCardView(store: store, item: $0) }
        .alert("Поделиться местом", isPresented: $showShare) { Button("Ок") {} } message: { Text("Ссылка и доступ — в следующей сборке.") }
        .confirmationDialog("Удалить место и все вещи в нём?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { try? await store.deletePlace(placeId); dismiss() } }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 48)
                    .background(Theme.ink, in: Capsule()).padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast)
    }

    @ViewBuilder
    private func content(_ place: Place) -> some View {
        let editable = place.status == .open
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Button {
                        guard place.destinationId != nil else { return }
                        withAnimation(.snappy) { barExpanded.toggle() }
                    } label: { BoxTileView(place: place, size: 112) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("\(place.kind.title) без названия", text: $title, axis: .vertical)
                            .font(.system(size: 22, weight: .heavy)).lineLimit(3)
                            .focused($titleFocused).submitLabel(.done).disabled(!editable)
                            .onChange(of: titleFocused) { _, f in if !f { saveTitle() } }
                        Text(subtitle(place)).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 8)
                }

                StatusBarView(place: place, destinations: store.destinations, itemsCount: items.count,
                              takenCount: items.filter(\.isTaken).count, expanded: $barExpanded,
                              onSelect: { d in Task { try? await store.updatePlace(placeId, destinationId: .some(d.id)) } },
                              onLock: { Task { await toggleLock(place) } })
                .modifier(Shake(animatableData: shakes))

                Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)

                if mode == .photos {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 14) {
                        CameraTile(enabled: editable) { showCamera = true }
                        ForEach(items) { it in
                            ItemCell(item: it, status: place.status,
                                     onMinus: { openItem = it },
                                     onTake: { Task { try? await store.updateItem(it.id, taken: !it.isTaken) } },
                                     onTap: { openItem = it })
                        }
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        if editable {
                            Button { showCamera = true } label: {
                                Label("Снять вещь", systemImage: "camera.fill")
                            }.buttonStyle(PrimaryButtonStyle())
                        }
                        ForEach(items) { it in
                            ItemRow(item: it, status: place.status,
                                    onMinus: { openItem = it },
                                    onTake: { Task { try? await store.updateItem(it.id, taken: !it.isTaken) } },
                                    onTap: { openItem = it })
                        }
                    }
                }
                if items.isEmpty {
                    Text(editable ? "Снимите первую вещь — подпись появится сама." : "Вещей нет.")
                        .font(.subheadline).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 8)
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func subtitle(_ p: Place) -> String {
        var s = "\(p.kind.numberLabel) № \(p.number) · " + Plural.things(items.count)
        if p.shared { s += " · общая" }
        return s
    }

    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = place, t != p.title else { return }
        Task { try? await store.updatePlace(placeId, title: t) }
    }

    private func toggleLock(_ p: Place) async {
        let next: PlaceStatus
        switch p.status {
        case .open:
            guard p.destinationId != nil else {
                withAnimation(.snappy) { barExpanded = true }
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }; return
            }
            next = .packed
        case .packed: next = .unpacking
        case .unpacking: next = .packed
        }
        do {
            try await store.updatePlace(placeId, status: next)
            show(next == .packed ? "Запаковано" : "Распаковка началась")
        } catch { show(error.localizedDescription) }
    }

    private func show(_ text: String) {
        toast = text
        Task { try? await Task.sleep(for: .seconds(2)); if toast == text { toast = nil } }
    }
}

/// Лёгкая тряска плашки, когда пытаются запаковать без направления.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 6), y: 0))
    }
}
