import SwiftUI
import PhotosUI

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
    @State private var lockDialog: LockDialog? = nil
    @State private var visible = false
    @State private var showPackCard = false
    @State private var barTop: CGFloat = 0
    @State private var stopTask: Task<Void, Never>? = nil
    @State private var openItem: Item? = nil
    @State private var toast: Toast? = nil
    struct Toast: Equatable { var text: String; var undoId: UUID? = nil }
    @State private var undoAction: (() async -> Void)? = nil
    @State private var shakes: CGFloat = 0
    // Поиск внутри места (лупа в шапке — как на главном).
    @State private var query = ""
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    // Фото самого места
    @State private var placePhotoMenu = false
    @State private var placeCamera = false
    @State private var placePickerItem: PhotosPickerItem? = nil
    @State private var showPlacePicker = false
    @State private var placePhotoViewer = false
    @FocusState private var titleFocused: Bool
    @Environment(\.scenePhase) private var scenePhase

    enum Mode: String, CaseIterable { case photos = "Фото", list = "Список" }
    enum LockDialog: Identifiable { case pack, packed, unpacking, done; var id: Int { hashValue } }

    private var place: Place? { store.place(placeId) }
    private var allItems: [Item] { store.items(of: placeId) }
    /// В сетке и списке — только совпавшие с поиском (пустой запрос — все).
    private var items: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? allItems : allItems.filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    var body: some View {
        Group {
            if let place { content(place) } else { ProgressView() }
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    withAnimation(.snappy) { showSearch.toggle() }
                    if showSearch { searchFocused = true } else { query = "" }
                } label: { Image(systemName: showSearch ? "magnifyingglass.circle.fill" : "magnifyingglass") }
                Button { showShare = true } label: { Image(systemName: "square.and.arrow.up") }
                Menu {
                    Button { showEdit = true } label: { Label("Изменить место", systemImage: "pencil") }
                    Button { showDest = true } label: { Label("Куда едет", systemImage: "mappin.and.ellipse") }
                        .disabled(place?.status != .open)   // у запакованной коробки направление не меняют
                    Button {} label: { Label("Отправить как посылку", systemImage: "paperplane") }.disabled(true)
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить место", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear {
            title = place?.title ?? ""
            // Первое место каждого типа: один раз предлагаем сразу дать название (необязательно)
            if let p = place, p.title.isEmpty, p.status == .open, items.isEmpty {
                let key = "named_hint_" + p.kind.rawValue
                if !UserDefaults.standard.bool(forKey: key) {
                    UserDefaults.standard.set(true, forKey: key)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { titleFocused = true }
                }
            }
        }
        .onDisappear { saveTitle(); if !showCamera { CameraModel.shared.stop() } }
        .onChange(of: scenePhase) { _, p in if p == .active { CameraModel.shared.start() } else { CameraModel.shared.stop() } }
        .onChange(of: place?.destinationId) { _, new in if new != nil { barExpanded = false } }
        .onChange(of: showCamera) { _, on in if !on { CameraModel.shared.start() } }
        .fullScreenCover(isPresented: $showCamera) { CameraView(store: store, placeId: placeId) }
        .sheet(isPresented: $showDest) { DestinationPickerView(store: store, placeId: placeId) }
        .sheet(isPresented: $showEdit) { EditPlaceView(store: store, placeId: placeId) }
        .confirmationDialog("Фото места", isPresented: $placePhotoMenu, titleVisibility: .hidden) {
            Button("Снять фото места") { placeCamera = true }
            Button("Выбрать из галереи") { showPlacePicker = true }
            if place?.numberPhoto != nil { Button("Удалить фото", role: .destructive) { Task { await setPlacePhoto(nil) } } }
            Button("Отмена", role: .cancel) {}
        }
        .photosPicker(isPresented: $showPlacePicker, selection: $placePickerItem, matching: .images)
        .onChange(of: placePickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { await setPlacePhoto(img) }
                placePickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $placeCamera) {
            CameraPicker { img in if let img { Task { await setPlacePhoto(img) } } }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $placePhotoViewer) {
            if let place {
                PlacePhotoViewer(place: place, editable: place.status == .open,
                                 onReplace: { placePhotoViewer = false; placePhotoMenu = true },
                                 onDelete: { placePhotoViewer = false; Task { await setPlacePhoto(nil) } })
            }
        }
        .sheet(item: $openItem) { it in
            ItemCardView(store: store, item: it) { removed in
                // Вариант «удалить сразу + Отменить» (как в Фото/Заметках): 5 секунд на возврат.
                undoAction = { try? await store.restoreItem(removed) }
                show("Вещь удалена", undo: removed.id, seconds: 5)
            }
        }
        .sheet(isPresented: $showShare) { SharePlaceView(store: store, placeId: placeId) }
        .confirmationDialog(lockTitle, isPresented: .init(get: { lockDialog != nil }, set: { if !$0 { lockDialog = nil } }), titleVisibility: .visible) {
            switch lockDialog {
            case .pack: EmptyView()
            case .packed:
                Button("Открыть и доложить вещи") { setStatus(.open, toast: "Открыто — можно добавлять") }
                Button("Начать распаковку") { setStatus(.unpacking, toast: "Распаковка началась") }
            case .unpacking:
                if allTaken { Button("Коробка разобрана") { setStatus(.done, toast: "Разобрана") } }
                Button("Запаковать снова") { setStatus(.packed, toast: "Запаковано") }
                Button("Открыть и доложить вещи") { setStatus(.open, toast: "Открыто — можно добавлять") }
            case .done:
                Button("Вернуть в распаковку") { setStatus(.unpacking, toast: "Снова в распаковке") }
            case nil: EmptyView()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(lockMessage)
        }
        .confirmationDialog("Удалить место и все вещи в нём?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { try? await store.deletePlace(placeId); dismiss() } }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                HStack(spacing: 14) {
                    Text(toast.text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.onInk)
                    if toast.undoId != nil {
                        Button("Отменить") {
                            let action = undoAction; undoAction = nil; self.toast = nil
                            Task { await action?() }
                        }
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 18).frame(height: 48)
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
                        // Есть фото места — открываем крупно; нет — предлагаем снять.
                        if place.numberPhoto != nil { placePhotoViewer = true } else if editable { placePhotoMenu = true }
                    } label: { BoxTileView(place: place, size: 112, cameraHint: editable) }.buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Без названия", text: $title)   // тип и так в чипах ниже; «Чемодан или сумка без названия» не влезало
                            .font(.system(size: 22, weight: .heavy)).lineLimit(1)
                            .focused($titleFocused).submitLabel(.done).disabled(!editable)
                            .onSubmit { saveTitle(); titleFocused = false }
                            .onChange(of: titleFocused) { _, f in if !f { saveTitle() } }
                            .onChange(of: title) { _, _ in scheduleSave() }
                        FlowLayout(spacing: 6) {
                            ForEach(metaChips(place), id: \.self) { t in
                                Text(t).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                                    .padding(.horizontal, 9).frame(height: 24)
                                    .background(Theme.card, in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                StatusBarView(place: place, destinations: store.destinations, itemsCount: items.count,
                              takenCount: items.filter(\.isTaken).count, expanded: $barExpanded,
                              onSelect: { d in Task { try? await store.updatePlace(placeId, destinationId: .some(d.id)) } },
                              onLock: { Task { await toggleLock(place) } })
                .modifier(Shake(animatableData: shakes))
                .background(GeometryReader { g in
                    Color.clear.preference(key: BarTopKey.self, value: g.frame(in: .named("placeScreen")).minY)
                })

                if showSearch {
                    SearchField(text: $query, placeholder: "Найти вещь в этом месте", focused: $searchFocused)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Picker("", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) } }.pickerStyle(.segmented)

                if mode == .photos {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top), GridItem(.flexible(), spacing: 10, alignment: .top)], spacing: 14) {
                        CameraTile(enabled: editable) { showCamera = true }
                        ForEach(items) { it in
                            ItemCell(item: it, status: place.status, query: query,
                                     onMinus: { Task { await deleteWithUndo(it) } },
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
                            ItemRow(item: it, status: place.status, query: query,
                                    onMinus: { Task { await deleteWithUndo(it) } },
                                    onTake: { Task { try? await store.updateItem(it.id, taken: !it.isTaken) } },
                                    onTap: { openItem = it })
                        }
                    }
                }
                if items.isEmpty, !allItems.isEmpty {
                    Text("Ничего не нашлось").font(.subheadline).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity).padding(.top, 24)
                } else if allItems.isEmpty {
                    Text(editable ? "Снимите первую вещь — подпись появится сама." : "Вещей нет.")
                        .font(.subheadline).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.top, 8)
                }
                Color.clear.frame(height: 40)
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .coordinateSpace(name: "placeScreen")
        .onPreferenceChange(BarTopKey.self) { barTop = $0 }
        .overlay { if showPackCard { packCard(place) } }
    }

    /// Карточка «Запаковать?»: нижний лист по высоте содержимого, остальное затемнено.
    private func packCard(_ p: Place) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.18).ignoresSafeArea()
                .onTapGesture { withAnimation(.snappy) { showPackCard = false } }
            VStack(alignment: .leading, spacing: 14) {
                Text("Запаковать место № \(p.number)?").font(.system(size: 22, weight: .heavy))
                Text("Всё, что происходит дальше — запаковали, открыли, достали вещь, — остаётся в истории с датой.")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted).lineSpacing(3)
                    .padding(.bottom, 8)
                Button {
                    withAnimation(.snappy) { showPackCard = false }
                    setStatus(.packed, toast: "Запаковано")
                } label: { Label("Запаковать", systemImage: "lock.fill") }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Не сейчас") { withAnimation(.snappy) { showPackCard = false } }
                    .buttonStyle(PrimaryButtonStyle(fill: Theme.bg, ink: Theme.ink))
            }
            .padding(20).padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // Фон уходит под индикатор «домой»: иначе снизу остаётся серая полоса.
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22).fill(Theme.card)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: -4)
                    .ignoresSafeArea(edges: .bottom)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func metaChips(_ p: Place) -> [String] {
        var c = ["№ \(p.number)", p.kindTitle, Plural.things(items.count)]
        if p.shared { c.append("Общая") }
        return c
    }

    @State private var saveTask: Task<Void, Never>? = nil
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { try? await Task.sleep(for: .seconds(1)); if !Task.isCancelled { saveTitle() } }
    }
    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let p = place, t != p.title else { return }
        Task { try? await store.updatePlace(placeId, title: t) }
    }

    private func toggleLock(_ p: Place) async {
        titleFocused = false          // клавиатура от названия не должна оставаться под диалогом
        switch p.status {
        case .open:
            guard p.destinationId != nil else {
                withAnimation(.snappy) { barExpanded = true }
                withAnimation(.linear(duration: 0.4)) { shakes += 1 }; return
            }
            withAnimation(.snappy) { showPackCard = true }
        case .packed: lockDialog = .packed
        case .unpacking: lockDialog = .unpacking
        case .done: lockDialog = .done
        }
    }

    private func setStatus(_ next: PlaceStatus, toast text: String) {
        Task {
            do { try await store.updatePlace(placeId, status: next); show(text) }
            catch { show(error.localizedDescription) }
        }
    }

    private var allTaken: Bool { !items.isEmpty && items.allSatisfy(\.isTaken) }

    private var lockTitle: String {
        guard let p = place else { return "" }
        switch lockDialog {
        case .pack: return "Запаковать \(p.kind.numberLabel.lowercased()) № \(p.number)?"
        case .packed: return "\(p.kind.numberLabel) № \(p.number) запакована"
        case .unpacking: return allTaken ? "Всё достали" : "Распаковка"
        case .done: return "\(p.kind.numberLabel) № \(p.number) разобрана"
        case nil: return ""
        }
    }
    private var lockMessage: String {
        switch lockDialog {
        case .pack: return "После запаковки вещи не добавить, пока не откроете снова. Открыть можно в любой момент."
        case .packed: return "Что делаем?"
        case .unpacking: return allTaken ? "Отметьте коробку разобранной — она уйдёт из активных, вещи останутся в истории." : "Что делаем?"
        case .done: return "Вещи можно снова отмечать и возвращать."
        case nil: return ""
        }
    }

    /// Фото места: сжимаем как фото вещи, кладём локально под id места, заливаем под places/<id>/…; nil — удалить.
    private func setPlacePhoto(_ img: UIImage?) async {
        guard let img else {
            PhotoStore.deleteLocal(placeId)
            try? await store.updatePlace(placeId, numberPhoto: .some(nil))
            return
        }
        guard let data = PhotoStore.save(img, for: placeId) else { return }
        await PhotoStore.uploadPlacePhoto(placeId, photo: data.photo, thumb: data.thumb, store: store)
    }

    /// Удаление из списка (второе нажатие на урну): сразу, с «Отменить» в тосте.
    private func deleteWithUndo(_ it: Item) async {
        guard let removed = try? await store.deleteItem(it.id) else { return }
        undoAction = { try? await store.restoreItem(removed) }
        show("Вещь удалена", undo: removed.id, seconds: 5)
    }

    private func show(_ text: String, undo: UUID? = nil, seconds: Double = 2) {
        let t = Toast(text: text, undoId: undo)
        toast = t
        Task {
            try? await Task.sleep(for: .seconds(seconds))
            if toast == t {
                toast = nil
                if let id = undo { undoAction = nil; PhotoStore.deleteLocal(id) }   // окно «Отменить» закрылось — чистим локальное фото
            }
        }
    }
}

/// Лёгкая тряска плашки, когда пытаются запаковать без направления.
struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(animatableData * .pi * 6), y: 0))
    }
}

struct BarTopKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Фото места крупно: зум щипком, «Заменить» / «Удалить» (как просмотр аватарки).
struct PlacePhotoViewer: View {
    let place: Place
    let editable: Bool
    let onReplace: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage? = nil
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
                    .scaleEffect(zoom)
                    .gesture(MagnifyGesture().onChanged { v in zoom = min(max(zoomStart * v.magnification, 1), 5) }
                        .onEnded { _ in zoomStart = zoom; if zoom < 1.05 { withAnimation(.snappy) { zoom = 1; zoomStart = 1 } } })
                    .onTapGesture(count: 2) { withAnimation(.snappy) { zoom = zoom > 1 ? 1 : 2.5; zoomStart = zoom } }
            } else { ProgressView().tint(.white) }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.onInk)
                            .frame(width: 44, height: 44).background(.black.opacity(0.45), in: Circle())
                    }
                    Spacer()
                    Text("\(place.kind.numberLabel) № \(place.number)").font(.headline).foregroundStyle(Theme.onInk)
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
                if editable {
                    HStack(spacing: 12) {
                        Button(action: onReplace) { Label("Заменить", systemImage: "camera") }
                            .buttonStyle(PrimaryButtonStyle(fill: Theme.card.opacity(0.15), ink: Theme.onInk))
                        Button(action: onDelete) { Label("Удалить", systemImage: "trash") }
                            .buttonStyle(PrimaryButtonStyle(fill: Theme.card.opacity(0.15), ink: .red))
                    }
                    .padding(16)
                }
            }
        }
        .task { image = await PhotoStore.image(forPlace: place, thumb: false) }
    }
}
