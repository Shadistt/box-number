import SwiftUI
import PDFKit

/// Превью вещи: локальный файл или подписанная ссылка R2.
struct ItemThumb: View {
    let item: Item
    var size: CGFloat? = nil
    var full = false
    @State private var image: UIImage? = nil
    @State private var changes = PhotoStore.Changes.shared

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Theme.tile
                        Image(systemName: "photo").foregroundStyle(Theme.muted)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size.map { $0 * 0.25 } ?? 16))
        .task(id: "\(item.id)-\(changes.version)") {
            guard full else { image = await PhotoStore.image(for: item, thumb: true); return }
            // Крупно (02.11.2026): сразу миниатюра (она почти всегда уже на телефоне), крупное фото подменяет её, когда скачается.
            if image == nil { image = await PhotoStore.image(for: item, thumb: true) }
            if let big = await PhotoStore.image(for: item, thumb: false) { withAnimation(.easeOut(duration: 0.2)) { image = big } }
        }
    }
}

/// Плитка вещи в сетке «Фото».
struct ItemCell: View {
    let item: Item
    let status: PlaceStatus
    var query = ""
    let onMinus: () -> Void
    let onTake: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Button(action: onTap) { ItemThumb(item: item) }.buttonStyle(.plain)
                    .opacity(item.isTaken ? 0.45 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if let n = item.docPages {   // документ: «PDF · 3»
                            Text("PDF · \(n)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.white)
                                .padding(.horizontal, 6).frame(height: 18).background(Theme.accent, in: Capsule()).padding(5)
                        }
                    }
                if status == .open {
                    TwoStepDelete(onDelete: onMinus) { armed in
                        Image(systemName: armed ? "trash.fill" : "minus").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(armed ? Color.red : .black.opacity(0.55), in: Circle())
                    }.padding(6)
                } else if status == .unpacking {
                    Button(action: onTake) {
                        Text(item.isTaken ? "Вернуть" : "Достал(а)").font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(item.isTaken ? Theme.bg : Theme.accent, in: Capsule()).foregroundStyle(Theme.ink)
                    }.padding(6)
                }
            }
            Text(highlight(item.titleWithQuantity, query)).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                .foregroundStyle(item.isTaken ? Theme.muted : Theme.ink).strikethrough(item.isTaken)
        }
    }
}

/// Строка вещи в режиме «Список».
struct ItemRow: View {
    let item: Item
    let status: PlaceStatus
    var query = ""
    let onMinus: () -> Void
    let onTake: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) { ItemThumb(item: item, size: 48) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight(item.titleWithQuantity, query)).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    .foregroundStyle(item.isTaken ? Theme.muted : Theme.ink).strikethrough(item.isTaken)
                if let t = item.takenAt { Text("Достали " + t.formatted(.dateTime.day().month())).font(.caption).foregroundStyle(Theme.muted) }
                else if item.captionSource == .ai { Text("AI-подпись").font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer()
            if status == .open {
                TwoStepDelete(onDelete: onMinus) { armed in
                    Image(systemName: armed ? "trash.circle.fill" : "minus.circle").font(.title3).foregroundStyle(armed ? .red : Theme.muted)
                }
            } else if status == .unpacking {
                Button(action: onTake) {
                    Text(item.isTaken ? "Вернуть" : "Достал(а)").font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(item.isTaken ? Theme.bg : Theme.accent, in: Capsule()).foregroundStyle(Theme.ink)
                }
            }
        }
        .padding(12).background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Карточка вещи: фото, подпись, переложить, удалить.
struct ItemCardView: View {
    let store: PlacesStore
    let item: Item
    /// Удаление без диалога: карточка закрывается, родитель показывает тост «Отменить».
    var onDeleted: ((Item) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var showMove = false
    @State private var suggestions: [String] = []
    @State private var editPhoto: EditablePhoto? = nil
    @State private var retake = false
    @State private var photoVersion = 0
    @State private var quantity = 1
    @State private var rescan = false

    private var place: Place? { store.place(item.placeId) }
    private var editable: Bool { place?.status == .open }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if item.isDocument {
                        // берём свежую версию из стора: после «Досканировать» число страниц меняется
                        DocumentPreview(item: store.items(of: item.placeId).first { $0.id == item.id } ?? item,
                                        editable: editable, onRescan: { rescan = true })
                    } else {
                    ItemThumb(item: item, full: true).frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        .id(photoVersion)
                        .overlay(alignment: .bottomTrailing) {
                            if editable {
                                HStack(spacing: 8) {
                                    Button { retake = true } label: {
                                        Label("Переснять", systemImage: "camera").font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 12).frame(height: 32).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                                    }
                                    Button {
                                        Task { if let img = await PhotoStore.image(for: item, thumb: false) { editPhoto = EditablePhoto(image: img) } }
                                    } label: {
                                        Label("Обрезать · повернуть", systemImage: "crop.rotate").font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 12).frame(height: 32).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                                    }
                                }
                                .padding(10)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ПОДПИСЬ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        // Название и количество в одной строке (паттерн Gojek / Careem, Mobbin): «Кружка  − 2 +».
                        HStack(spacing: 8) {
                            TextField("Что это", text: $title, axis: .vertical).font(.system(size: 18, weight: .semibold))
                                .disabled(!editable)
                                .onSubmit(save)
                            QuantityStepper(value: $quantity, enabled: editable) { q in
                                Task { try? await store.updateInventory(item.id, quantity: q) }
                            }
                        }
                        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8).frame(minHeight: 54)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        if editable && !suggestions.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 8) {
                                    ForEach(suggestions, id: \.self) { s in
                                        Chip(title: s, selected: s == title.trimmingCharacters(in: .whitespaces)) { title = s; save() }
                                    }
                                }
                            }.scrollIndicators(.hidden)
                        }
                        if item.captionSource == .ai { Text("Подпись предложена автоматически — исправьте, если неточно.").font(.caption).foregroundStyle(Theme.muted) }
                    }
                    if let place {
                        Text("Лежит в: \(place.kind.numberLabel) № \(place.number) · \(place.displayTitle)").font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    InventoryBlock(store: store, item: item, editable: editable)
                    if item.isEncrypted {
                        Label("В сейфе: название и фото зашифрованы на этом iPhone.", systemImage: "lock.fill").font(.caption).foregroundStyle(Theme.muted)
                    }
                    if editable {
                        // Из сейфа и в сейф вещи не перекладываются: ключ личный, фото пришлось бы расшифровывать.
                        if !item.isEncrypted {
                            Button { showMove = true } label: { Label("Переложить в другое место", systemImage: "arrow.right.square") }
                                .buttonStyle(PrimaryButtonStyle(fill: Theme.card, ink: Theme.ink))
                        }
                        Button(role: .destructive) { Task { await deleteNow() } } label: { Label("Удалить вещь", systemImage: "trash") }
                            .buttonStyle(PrimaryButtonStyle(fill: Theme.card, ink: .red))
                    } else {
                        Text("Место запаковано — редактировать нельзя.").font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Вещь").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Готово") { save(); dismiss() } }
            }
            .onAppear { title = item.title; quantity = item.quantity }
            .task {
                // Сейф: распознавание выключено, фото не уходит в модель
                // По миниатюре (320 px — модели хватает 224), она уже на телефоне: подсказки сразу, не после загрузки крупного фото.
                if editable, !item.isEncrypted, item.isDocument, let page = await PhotoStore.image(for: item, thumb: false) {
                    suggestions = await DocScanner.titleSuggestions(page)    // документ: по тексту первой страницы
                } else if editable, !item.isEncrypted, let img = await PhotoStore.image(for: item, thumb: true) { suggestions = await Captioner.candidates(img) }
            }
            // Во весь экран, а не sheet поверх sheet'а — без «стопки окон» сзади.
            .fullScreenCover(isPresented: $rescan) {
                if let place { CameraView(store: store, placeId: place.id, appendTo: store.items(of: item.placeId).first { $0.id == item.id } ?? item) }
            }
            .onChange(of: rescan) { _, on in if on { Task { await DocStore.ensurePages(item) } } }
            .fullScreenCover(isPresented: $showMove) {
                MoveItemView(store: store, item: item) { dismiss() }
            }
            .fullScreenCover(item: $editPhoto) { p in
                PhotoEditView(image: p.image) { edited in Task { await replacePhoto(edited) } }
            }
            // Переснять ту же вещь: системная камера (задняя), фото заменяется под тем же ключом.
            .fullScreenCover(isPresented: $retake) {
                CameraPicker { img in if let img { Task { await replacePhoto(img) } } }.ignoresSafeArea()
            }
        }
    }

    /// Удаляем сразу (мягко) — вернуть можно тостом «Отменить» на экране места.
    private func deleteNow() async {
        guard let removed = try? await store.deleteItem(item.id) else { return }
        dismiss()
        onDeleted?(removed)
    }

    /// Новое фото под тем же ключом: локально сразу, в R2 — следом; подсказки подписи пересчитываем.
    private func replacePhoto(_ img: UIImage) async {
        guard let data = PhotoStore.save(img, for: item.id, encrypted: item.isEncrypted) else { return }
        photoVersion += 1
        await PhotoStore.upload(item.id, photo: data.photo, thumb: data.thumb, store: store)
        if !item.isEncrypted { suggestions = await Captioner.candidates(img) }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard editable, !t.isEmpty, t != item.title else { return }
        Task { try? await store.updateItem(item.id, title: t, source: .user) }
    }
}

/// «Переложить»: выбор другого открытого места этого переезда.
struct MoveItemView: View {
    let store: PlacesStore
    let item: Item
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: UUID? = nil
    @State private var busy = false

    private var target: Place? { selected.flatMap { store.place($0) } }
    private var changed: Bool { selected != nil && selected != item.placeId }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(store.places.filter { !$0.kind.isSafe }.enumerated()), id: \.element.id) { i, p in
                        let open = p.status == .open
                        Button { if open { selected = p.id } } label: {
                            HStack(spacing: 12) {
                                // Галочка как в «Куда едет»; текущее место отмечено с самого начала.
                                Image(systemName: selected == p.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(selected == p.id ? Theme.accent : Theme.line)
                                KindIcon(kind: p.kind, size: 17, weight: .semibold)
                                    .frame(width: 28)          // одинаковая ширина — текст начинается в одну линию
                                    .foregroundStyle(open ? Theme.ink : Theme.muted)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("№ \(p.number) · \(p.displayTitle)").font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(open ? Theme.ink : Theme.muted).lineLimit(1)
                                    Text(p.id == item.placeId ? "Лежит здесь" : open ? Plural.things(store.items(of: p.id).count) : "Запаковано")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16).frame(minHeight: 56)
                            .overlay(alignment: .top) { if i > 0 { Divider().padding(.leading, 56) } }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!open)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
                .padding(16)
                .padding(.bottom, 80)
            }
            .background(Theme.bg)
            .safeAreaInset(edge: .bottom) {
                Button {
                    guard let selected else { return }
                    busy = true
                    Task { try? await store.updateItem(item.id, placeId: selected); busy = false; dismiss(); onDone() }
                } label: {
                    if busy { ProgressView().tint(Theme.onInk) }
                    else { Text(target.map { "Переложить в № \($0.number)" } ?? "Переложить") }
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(!changed || busy).opacity(changed ? 1 : 0.5)
                .padding(16).background(Theme.bg)
            }
            .navigationTitle("Переложить в").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .onAppear { selected = item.placeId }
        }
    }
}

struct EditablePhoto: Identifiable { let id = UUID(); let image: UIImage }

/// Минус → красная урна → удаление: два нажатия, без диалога. Через 3 секунды без второго нажатия возвращается к минусу.
struct TwoStepDelete<Label: View>: View {
    let onDelete: () -> Void
    @ViewBuilder let label: (Bool) -> Label
    @State private var armed = false
    @State private var disarm: Task<Void, Never>?

    var body: some View {
        Button {
            if armed { armed = false; disarm?.cancel(); onDelete() }
            else {
                withAnimation(.snappy) { armed = true }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                disarm?.cancel()
                disarm = Task { try? await Task.sleep(for: .seconds(3)); if !Task.isCancelled { withAnimation(.snappy) { armed = false } } }
            }
        } label: { label(armed) }
        .buttonStyle(.plain)
    }
}

/// Задняя камера через системный контроллер — для «Переснять» в карточке вещи.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.onPick(info[.originalImage] as? UIImage); parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onPick(nil); parent.dismiss() }
    }
}


/// «− 2 +» в строке названия: компактно, кнопки 32 pt, диапазон 1…999.
struct QuantityStepper: View {
    @Binding var value: Int
    var enabled = true
    let onChange: (Int) -> Void
    var body: some View {
        HStack(spacing: 2) {
            step("minus", -1).disabled(!enabled || value <= 1)
            Text("\(value)").font(.system(size: 17, weight: .bold)).monospacedDigit().frame(minWidth: 26)
            step("plus", 1).disabled(!enabled || value >= 999)
        }
        .padding(3).background(Theme.bg, in: Capsule())
        .accessibilityElement(children: .ignore).accessibilityLabel("Количество \(value)")
        .accessibilityAdjustableAction { d in
            switch d { case .increment: change(1); case .decrement: change(-1); default: break }
        }
    }
    private func step(_ icon: String, _ d: Int) -> some View {
        Button { change(d) } label: {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).frame(width: 32, height: 32)
                .background(Theme.card, in: Circle()).foregroundStyle(Theme.ink)
        }.buttonStyle(.plain)
    }
    private func change(_ d: Int) {
        let v = min(max(value + d, 1), 999); guard v != value else { return }
        value = v; UISelectionFeedbackGenerator().selectionChanged(); onChange(v)
    }
}

/// «Для описи» (ТЗ §16): свёрнутая строка с итогом справа; раскрывается в поля вес и оценочная стоимость.
/// Стоимость — за штуку, в валюте устройства (валюта переезда — следующим шагом), хранится как ввели.
struct InventoryBlock: View {
    let store: PlacesStore
    let item: Item
    let editable: Bool
    @State private var open = false
    @State private var weight = ""
    @State private var price = ""
    @State private var unit = WeightUnit.current
    @State private var pickedCurrency: String? = nil
    @FocusState private var focus: Field?
    enum Field { case weight, price }

    private var currency: String { pickedCurrency ?? item.valueCurrency ?? Locale.current.currency?.identifier ?? "EUR" }
    private var summary: String {
        var parts: [String] = []
        if let w = item.weightKg { parts.append(unit.summary(w)) }
        if let v = item.value { parts.append((v * Double(item.quantity)).formatted(.currency(code: currency).precision(.fractionLength(0...2)))) }
        return parts.isEmpty ? "не заполнено" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 0) {
            Button { withAnimation(.snappy) { open.toggle() } } label: {
                HStack {
                    Label("Для описи", systemImage: "list.clipboard").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.ink)
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
                field("Вес", text: $weight, f: .weight) {
                    UnitMenuButton(title: unit.title, options: WeightUnit.allCases, label: { $0.name }, selected: unit, enabled: editable) { u in
                        let kgValue = parse(weight).map { $0 * unit.kg }
                        unit = u; WeightUnit.current = u
                        weight = u.show(kgValue)
                    }
                }
                Divider().padding(.leading, 16)
                field(item.quantity > 1 ? "Стоимость за штуку" : "Оценочная стоимость", text: $price, f: .price) {
                    UnitMenuButton(title: currency, options: InventoryCurrency.list, label: InventoryCurrency.name, selected: currency, enabled: editable) { c in
                        pickedCurrency = c; save(force: true)
                    }
                }
                Text("Необязательно. Видно только в описи для перевозчика, страховой или таможни.")
                    .font(.caption).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.bottom, 12)
            }
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .onAppear {
            weight = unit.show(item.weightKg)
            price = item.value.map { $0.formatted(.number.precision(.fractionLength(0...2))) } ?? ""
        }
        .onChange(of: focus) { old, _ in if old != nil { save() } }
        .onDisappear { save() }
    }

    private func field<U: View>(_ label: String, text: Binding<String>, f: Field, @ViewBuilder unit: () -> U) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 16)).foregroundStyle(Theme.ink)
            Spacer()
            TextField("0", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .semibold)).focused($focus, equals: f).disabled(!editable)
                .padding(.horizontal, 10).frame(width: 96, height: 34)
                .background(editable ? Theme.bg : .clear, in: RoundedRectangle(cornerRadius: 8))
            unit()
        }
        .padding(.horizontal, 16).frame(minHeight: 50)
    }

    /// Пустое поле — очистить; число с запятой или точкой.
    private func parse(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
        return t.isEmpty ? nil : Double(t)
    }
    private func save(force: Bool = false) {
        guard editable else { return }
        let w = parse(weight).map { ($0 * unit.kg * 100).rounded() / 100 }, v = parse(price)
        guard force || w != item.weightKg || v != item.value else { return }
        Task { try? await store.updateInventory(item.id, weightKg: .some(w), value: .some(v), currency: .some(v == nil ? nil : currency)) }
    }
}


/// Документ в карточке вещи: страницы PDF (листаются), «Поделиться» и «Досканировать».
struct DocumentPreview: View {
    let item: Item
    let editable: Bool
    let onRescan: () -> Void
    @State private var pdf: Data? = nil
    @State private var shareURL: URL? = nil
    @State private var full = false
    @State private var loading = true

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Theme.tile)
                if let pdf { PDFKitView(data: pdf).clipShape(RoundedRectangle(cornerRadius: 16)) }
                else if loading { ProgressView() }
                else { Label(item.isEncrypted ? "Сейф закрыт" : "PDF не загрузился", systemImage: "doc").foregroundStyle(Theme.muted) }
            }
            .frame(height: 380)
            .overlay(alignment: .topTrailing) {
                if pdf != nil {
                    HStack(spacing: 6) {
                        if let shareURL {
                            ShareLink(item: shareURL) { Label("Поделиться", systemImage: "square.and.arrow.up") }
                                .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 12).frame(height: 32)
                                .background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                        }
                        Button { full = true } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .bold))
                                .frame(width: 32, height: 32).background(.black.opacity(0.55), in: Circle()).foregroundStyle(.white)
                        }
                    }
                    .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                if let n = item.docPages, n > 1 {
                    Text("\(n) стр. · листайте").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 10).frame(height: 26).background(.black.opacity(0.55), in: Capsule()).padding(10)
                }
            }
            if editable {
                Button(action: onRescan) { Label("Досканировать страницы", systemImage: "doc.badge.plus") }
                    .buttonStyle(PrimaryButtonStyle(fill: Theme.card, ink: Theme.ink))
            }
        }
        .task(id: item.docPages) {
            if let d = await DocStore.pdf(for: item) { pdf = d; shareURL = DocStore.shareFile(d, title: item.title) }
            loading = false
        }
        .fullScreenCover(isPresented: $full) {
            if let pdf {
                NavigationStack {
                    PDFKitView(data: pdf).ignoresSafeArea(edges: .bottom)
                        .navigationTitle(item.title).navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { full = false } }
                            if let shareURL { ToolbarItem(placement: .primaryAction) { ShareLink(item: shareURL) } }
                        }
                }
            }
        }
    }
}

/// PDFKit в SwiftUI: страницы одна под другой, по ширине экрана.
struct PDFKitView: UIViewRepresentable {
    let data: Data
    final class Coordinator { var data: Data? }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PDFView {
        context.coordinator.data = data
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.backgroundColor = .clear
        v.document = PDFDocument(data: data)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if context.coordinator.data != data { context.coordinator.data = data; v.document = PDFDocument(data: data) }
    }
}
