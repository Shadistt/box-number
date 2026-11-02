import SwiftUI
import PhotosUI
import Supabase

/// Карточка места (02.11.2026, утверждено по макету place2.png) — в стиле карточки вещи:
/// фото номера сверху (или пустое состояние с кнопкой), подпись с подсказками над клавиатурой,
/// номер и тип, пометки §13, «Для описи» места, «Удалить место».
/// Открывается тапом по плитке на экране места (карандаш в углу) и из «•••» → «Изменить место».
struct PlaceCardView: View {
    let store: PlacesStore
    let placeId: UUID
    /// Роль «edit» (place_role). Кто только смотрит — всё только для чтения.
    let canEdit: Bool
    let onDeleted: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var number = ""
    @State private var numberError: String? = nil
    @State private var showType = false
    @State private var photo: UIImage? = nil
    @State private var photoMenu = false
    @State private var camera = false
    @State private var showPicker = false
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var editPhoto: EditablePhoto? = nil
    @State private var viewer = false
    @State private var confirmDelete = false
    @State private var suggestions: [String] = []
    @State private var changes = PhotoStore.Changes.shared
    @FocusState private var focus: Field?
    enum Field: Hashable { case title, number }

    private var place: Place? { store.place(placeId) }
    private var isSafe: Bool { place?.kind.isSafe == true }
    @State private var safe = SafeSession.shared
    /// Сейф удаляется только открытым (решено 02.11.2026).
    private var safeLocked: Bool { isSafe && !safe.isOpen }
    /// Фото, подпись, номер, тип — только у открытого места. Пометки и опись — всегда (вес меряют уже запакованным).
    private var contentEditable: Bool { canEdit && place?.status == .open }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let place {
                    VStack(alignment: .leading, spacing: 16) {
                        if !isSafe { photoBlock(place) }
                        titleBlock
                        numberTypeBlock(place)
                        flagsBlock(place)
                        PlaceInventoryBlock(store: store, place: place, editable: canEdit)
                        if !contentEditable && canEdit {
                            Text("Место запаковано — фото, подпись, номер и тип не меняются. Пометки и опись — можно.")
                                .font(.footnote).foregroundStyle(Theme.muted)
                        }
                        if canEdit {
                            Button(role: .destructive) { confirmDelete = true } label: { Label(isSafe ? "Удалить сейф" : "Удалить место", systemImage: "trash") }
                                .buttonStyle(PrimaryButtonStyle(fill: Theme.card, ink: .red))
                                .disabled(safeLocked).opacity(safeLocked ? 0.5 : 1)
                            if safeLocked {
                                Text("Удалить сейф можно только открытым.").font(.footnote).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .padding(16)
                } else {
                    ProgressView().padding(.top, 60)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg)
            .navigationTitle("Место").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { Task { if await saveAll() { dismiss() } } }.fontWeight(.bold)
                }
                // Подсказки подписи над клавиатурой: только у поля «Подпись», только если есть что предложить.
                ToolbarItemGroup(placement: .keyboard) {
                    if focus == .title && !suggestions.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkle").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                                ForEach(suggestions, id: \.self) { s in
                                    Button { title = s; focus = nil; saveTitle() } label: {
                                        Text(s).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.ink)
                                            .padding(.horizontal, 11).frame(height: 32).background(Theme.card, in: Capsule())
                                    }.buttonStyle(.plain)
                                }
                            }
                        }.scrollIndicators(.hidden)
                    }
                }
            }
            .onAppear {
                title = place?.title ?? ""; number = place?.number ?? ""
            }
            .task(id: "\(place?.numberPhoto ?? "")-\(changes.version)") {
                guard let place, place.numberPhoto != nil else { photo = nil; return }
                photo = await PhotoStore.image(forPlace: place, thumb: false)
            }
            .task {
                // Сейф: содержимое зашифровано и в подсказки не идёт.
                guard contentEditable, !isSafe else { return }
                suggestions = await PlaceTitleSuggester.suggest(itemTitles: store.items(of: placeId).map(\.title))
            }
            .onChange(of: focus) { old, _ in
                if old == .title { saveTitle() }
                if old == .number { Task { await saveNumber() } }
            }
            .sheet(isPresented: $showType) {
                if let place {
                    TypePickerView(selected: place.kind, customText: place.customKind ?? "") { k, c in
                        Task { try? await store.updatePlace(placeId, kind: k, customKind: .some(k == .custom ? c : nil)) }
                    }
                }
            }
            .confirmationDialog("Фото номера", isPresented: $photoMenu, titleVisibility: .hidden) {
                Button("Снять фото") { camera = true }
                Button("Выбрать из галереи") { showPicker = true }
                if place?.numberPhoto != nil { Button("Удалить фото", role: .destructive) { Task { await setPhoto(nil) } } }
                Button("Отмена", role: .cancel) {}
            }
            .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { await setPhoto(img) }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { img in if let img { Task { await setPhoto(img) } } }.ignoresSafeArea()
            }
            .fullScreenCover(item: $editPhoto) { p in
                PhotoEditView(image: p.image) { edited in Task { await setPhoto(edited) } }
            }
            .fullScreenCover(isPresented: $viewer) {
                if let place {
                    PlacePhotoViewer(place: place, editable: contentEditable,
                                     onReplace: { viewer = false; photoMenu = true },
                                     onDelete: { viewer = false; Task { await setPhoto(nil) } })
                }
            }
            .confirmationDialog("Удалить место и все вещи в нём?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    Task { try? await store.deletePlace(placeId); dismiss(); onDeleted() }
                }
            }
        }
    }

    // MARK: фото

    @ViewBuilder
    private func photoBlock(_ place: Place) -> some View {
        if let photo {
            Color.clear.frame(maxWidth: .infinity).aspectRatio(4 / 3, contentMode: .fit)
                .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .contentShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { viewer = true }
                .overlay(alignment: .bottomTrailing) {
                    if contentEditable {
                        HStack(spacing: 8) {
                            Button { photoMenu = true } label: { overlayLabel("Переснять", "camera") }
                            Button { editPhoto = EditablePhoto(image: photo) } label: { overlayLabel("Обрезать · повернуть", "crop.rotate") }
                        }
                        .padding(10)
                    }
                }
        } else {
            // Пустое состояние: значок типа + номер; кнопка — только тем, кто может менять.
            VStack(spacing: 6) {
                Image(systemName: place.kind.symbol).font(.system(size: 30, weight: .semibold))
                Text(place.number).font(.system(size: 56, weight: .black, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                if contentEditable {
                    Text("Сфотографируйте номер на коробке —\nтак её легче узнать в списке")
                        .font(.footnote).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    Button { photoMenu = true } label: { Label("Сфотографировать номер", systemImage: "camera.fill") }
                        .font(.system(size: 16, weight: .semibold)).padding(.horizontal, 18).frame(height: 44)
                        .background(Theme.ink, in: Capsule()).foregroundStyle(Theme.onInk).padding(.top, 6)
                }
            }
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
            .background(Theme.tile, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func overlayLabel(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 12).frame(height: 32).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
    }

    private func setPhoto(_ img: UIImage?) async {
        guard let img else {
            PhotoStore.deleteLocal(placeId)
            try? await store.updatePlace(placeId, numberPhoto: .some(nil))
            photo = nil
            return
        }
        guard let data = PhotoStore.save(img, for: placeId) else { return }
        photo = img
        await PhotoStore.uploadPlacePhoto(placeId, photo: data.photo, thumb: data.thumb, store: store)
    }

    // MARK: подпись, номер, тип

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("ПОДПИСЬ")
            TextField("Без названия", text: $title)
                .font(.system(size: 18, weight: .semibold)).submitLabel(.done)
                .focused($focus, equals: .title).disabled(!contentEditable)
                .onSubmit { focus = nil }
                .padding(.horizontal, 16).frame(minHeight: 54)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func numberTypeBlock(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("НОМЕР И ТИП")
            VStack(spacing: 0) {
                HStack {
                    Text("Номер").font(.system(size: 16))
                    Spacer()
                    TextField("3, 3б…", text: $number).multilineTextAlignment(.trailing)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .focused($focus, equals: .number).disabled(!contentEditable).submitLabel(.done)
                        .onSubmit { focus = nil }
                        .frame(maxWidth: 140)
                }
                .padding(.horizontal, 16).frame(minHeight: 50)
                Divider().padding(.leading, 16)
                Button { if contentEditable { showType = true } } label: {
                    HStack(spacing: 8) {
                        Text("Тип").font(.system(size: 16)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: place.kind.symbol).foregroundStyle(Theme.ink)
                        Text(place.kindTitle).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        if contentEditable { Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted) }
                    }
                    .padding(.horizontal, 16).frame(minHeight: 50).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            if let numberError { Text(numberError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 4) }
        }
    }

    // MARK: пометки §13

    private func flagsBlock(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("ПОМЕТКИ")
            VStack(spacing: 0) {
                flagRow("Хрупкое", on: place.isFragile, key: "fragile") { PlaceFlagChip(kind: .fragile) }
                Divider().padding(.leading, 16)
                flagRow("Открыть первым", on: place.opensFirst, key: "open_first") { PlaceFlagChip(kind: .openFirst) }
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func flagRow<C: View>(_ label: String, on: Bool, key: String, @ViewBuilder chip: () -> C) -> some View {
        Toggle(isOn: Binding(get: { on }, set: { v in Task { try? await store.patchPlace(placeId, [key: .bool(v)]) } })) {
            HStack(spacing: 8) { Text(label).font(.system(size: 16)); chip() }
        }
        .tint(Theme.accent).disabled(!canEdit)
        .padding(.horizontal, 16).frame(minHeight: 50)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.horizontal, 4)
    }

    // MARK: сохранение

    private func saveTitle() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard contentEditable, let p = place, t != p.title else { return }
        Task { try? await store.updatePlace(placeId, title: t) }
    }

    @discardableResult
    private func saveNumber() async -> Bool {
        let n = number.trimmingCharacters(in: .whitespaces)
        guard contentEditable, let p = place, n != p.number else { numberError = nil; return true }
        guard !n.isEmpty else { numberError = "Введите номер"; return false }
        do {
            try await store.updatePlace(placeId, number: n); numberError = nil; return true
        } catch PlacesError.numberTaken {
            numberError = "№ \(n) уже есть в этом переезде"; return false
        } catch {
            numberError = "Не получилось сохранить номер"; return false
        }
    }

    private func saveAll() async -> Bool {
        focus = nil
        saveTitle()
        return await saveNumber()
    }
}

/// Чип пометки: «Хрупкое» — оранжевый контур, «Первым» — оранжевая заливка (ТЗ §13).
struct PlaceFlagChip: View {
    enum Kind { case fragile, openFirst }
    let kind: Kind
    var body: some View {
        Text(kind == .fragile ? "Хрупкое" : "Первым")
            .font(.system(size: 11, weight: .bold)).padding(.horizontal, 8).frame(height: 20)
            .foregroundStyle(kind == .fragile ? Theme.accent : .white)
            .background { Capsule().fill(kind == .fragile ? Color.clear : Theme.accent) }
            .overlay { if kind == .fragile { Capsule().stroke(Theme.accent, lineWidth: 1.5) } }
    }
}

/// «Для описи» места: вес, размер Д×Ш×В, стоимость по вещам и своя стоимость (переопределяет сумму, цены вещей не трогает).
struct PlaceInventoryBlock: View {
    let store: PlacesStore
    let place: Place
    let editable: Bool
    @State private var open = false
    @State private var weight = ""
    @State private var length = ""
    @State private var width = ""
    @State private var height = ""
    @State private var price = ""
    @FocusState private var focus: Field?
    enum Field { case weight, length, width, height, price }

    private var currency: String { place.valueCurrency ?? Locale.current.currency?.identifier ?? "EUR" }
    private var items: [Item] { store.items(of: place.id) }
    private var itemsValue: Double? {
        let priced = items.compactMap { i in i.value.map { $0 * Double(i.quantity) } }
        return priced.isEmpty ? nil : priced.reduce(0, +)
    }
    private var pricedCount: Int { items.filter { $0.value != nil }.count }
    private func money(_ v: Double) -> String { v.formatted(.currency(code: currency).precision(.fractionLength(0...2))) }
    private var summary: String {
        var parts: [String] = []
        if let w = place.weightKg { parts.append(w.formatted(.number.precision(.fractionLength(0...2))) + " кг") }
        if let v = place.value ?? itemsValue { parts.append((place.value == nil ? "≈ " : "") + money(v)) }
        return parts.isEmpty ? "не заполнено" : parts.joined(separator: " · ")
    }
    /// Объёмный вес для перевозчика: Д×Ш×В / 5000.
    private var volumetric: Double? {
        guard let l = place.lengthCm, let w = place.widthCm, let h = place.heightCm else { return nil }
        return Double(l * w * h) / 5000
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    Label("Вес, размер, стоимость", systemImage: "list.clipboard").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(summary).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .padding(.horizontal, 16).frame(minHeight: 52).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Divider().padding(.leading, 16)
                row("Вес места") { numField($weight, .weight, width: 90); unit("кг") }
                Divider().padding(.leading, 16)
                row("Размер, см") {
                    HStack(spacing: 4) {
                        dimField($length, .length); Text("×").foregroundStyle(Theme.muted)
                        dimField($width, .width); Text("×").foregroundStyle(Theme.muted)
                        dimField($height, .height)
                    }
                }
                if let volumetric {
                    Text("Объёмный вес ≈ \(volumetric.formatted(.number.precision(.fractionLength(0...1)))) кг (делитель 5000) — для перевозчика.")
                        .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.bottom, 10)
                }
                Divider().padding(.leading, 16)
                row("Стоимость по вещам") {
                    Text(itemsValue.map { "\(money($0)) · \(Plural.things(pricedCount))" } ?? "у вещей не указана")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                Divider().padding(.leading, 16)
                row("Своя стоимость места") {
                    numField($price, .price, width: 110); unit(currency)
                    if !price.isEmpty && editable {
                        Button { price = ""; save() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.buttonStyle(.plain)
                    }
                }
                Text(place.value != nil
                     ? "В описи и итогах — своя стоимость. Цены вещей сохранены; ✕ вернёт подсчёт по вещам."
                     : "Пусто — в итог идёт сумма по вещам. Укажете свою — она заменит сумму, цены вещей останутся.")
                    .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .onAppear(perform: load)
        .onChange(of: focus) { old, _ in if old != nil { save() } }
        .onDisappear { save() }
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16).frame(minHeight: 50)
    }
    private func unit(_ t: String) -> some View { Text(t).font(.subheadline).foregroundStyle(Theme.muted) }
    private func numField(_ text: Binding<String>, _ f: Field, width: CGFloat) -> some View {
        TextField("—", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            .font(.system(size: 16, weight: .semibold)).focused($focus, equals: f).disabled(!editable)
            .frame(maxWidth: width)
    }
    private func dimField(_ text: Binding<String>, _ f: Field) -> some View {
        TextField("—", text: text).keyboardType(.numberPad).multilineTextAlignment(.center)
            .font(.system(size: 15, weight: .semibold)).focused($focus, equals: f).disabled(!editable)
            .frame(width: 44, height: 32).background(Theme.bg, in: RoundedRectangle(cornerRadius: 8))
    }

    private func fmt(_ d: Double?) -> String { d.map { $0.formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) } ?? "" }
    private func load() {
        weight = fmt(place.weightKg); price = fmt(place.value)
        length = place.lengthCm.map(String.init) ?? ""; width = place.widthCm.map(String.init) ?? ""; height = place.heightCm.map(String.init) ?? ""
    }
    private func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return t.isEmpty ? nil : Double(t)
    }
    private func parseInt(_ s: String) -> Int? {
        guard let v = Int(s.trimmingCharacters(in: .whitespaces)), (1...1000).contains(v) else { return nil }
        return v
    }

    private func save() {
        guard editable else { return }
        var patch: [String: AnyJSON] = [:]
        func put<T: Equatable>(_ key: String, _ new: T?, _ old: T?, _ json: (T) -> AnyJSON) {
            if new != old { patch[key] = new.map(json) ?? .null }
        }
        put("weight_kg", parse(weight), place.weightKg) { .double($0) }
        put("length_cm", parseInt(length), place.lengthCm) { .integer($0) }
        put("width_cm", parseInt(width), place.widthCm) { .integer($0) }
        put("height_cm", parseInt(height), place.heightCm) { .integer($0) }
        let v = parse(price)
        put("value", v, place.value) { .double($0) }
        if v != nil, place.valueCurrency == nil { patch["value_currency"] = .string(currency) }
        guard !patch.isEmpty else { return }
        Task { try? await store.patchPlace(place.id, patch) }
    }
}
