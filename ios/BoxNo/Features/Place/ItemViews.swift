import SwiftUI

/// Превью вещи: локальный файл или подписанная ссылка R2.
struct ItemThumb: View {
    let item: Item
    var size: CGFloat? = nil
    var full = false
    @State private var image: UIImage? = nil

    var body: some View {
        Color.clear
            .frame(width: size, height: size)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color(hex: 0xE8E6E0)
                        Image(systemName: "photo").foregroundStyle(Theme.muted)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: size.map { $0 * 0.25 } ?? 16))
        .task(id: item.id) { image = await PhotoStore.image(for: item, thumb: !full) }
    }
}

/// Плитка вещи в сетке «Фото».
struct ItemCell: View {
    let item: Item
    let status: PlaceStatus
    let onMinus: () -> Void
    let onTake: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                Button(action: onTap) { ItemThumb(item: item) }.buttonStyle(.plain)
                    .opacity(item.isTaken ? 0.45 : 1)
                if status == .open {
                    Button(action: onMinus) {
                        Image(systemName: "minus").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white)
                            .frame(width: 26, height: 26).background(.black.opacity(0.55), in: Circle())
                    }.padding(6)
                } else if status == .unpacking {
                    Button(action: onTake) {
                        Text(item.isTaken ? "Вернуть" : "Достал(а)").font(.system(size: 12, weight: .bold))
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(item.isTaken ? Theme.bg : Theme.accent, in: Capsule()).foregroundStyle(Theme.ink)
                    }.padding(6)
                }
            }
            Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                .foregroundStyle(item.isTaken ? Theme.muted : Theme.ink).strikethrough(item.isTaken)
        }
    }
}

/// Строка вещи в режиме «Список».
struct ItemRow: View {
    let item: Item
    let status: PlaceStatus
    let onMinus: () -> Void
    let onTake: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onTap) { ItemThumb(item: item, size: 48) }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    .foregroundStyle(item.isTaken ? Theme.muted : Theme.ink).strikethrough(item.isTaken)
                if let t = item.takenAt { Text("Достали " + t.formatted(.dateTime.day().month())).font(.caption).foregroundStyle(Theme.muted) }
                else if item.captionSource == .ai { Text("AI-подпись").font(.caption).foregroundStyle(Theme.muted) }
            }
            Spacer()
            if status == .open {
                Button(action: onMinus) { Image(systemName: "minus.circle").font(.title3).foregroundStyle(Theme.muted) }
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
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var showMove = false
    @State private var confirmDelete = false
    @State private var suggestions: [String] = []
    @State private var editPhoto: EditablePhoto? = nil
    @State private var photoVersion = 0

    private var place: Place? { store.place(item.placeId) }
    private var editable: Bool { place?.status == .open }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ItemThumb(item: item, full: true).frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                        .id(photoVersion)
                        .overlay(alignment: .bottomTrailing) {
                            if editable {
                                Button {
                                    Task { if let img = await PhotoStore.image(for: item, thumb: false) { editPhoto = EditablePhoto(image: img) } }
                                } label: {
                                    Label("Обрезать · повернуть", systemImage: "crop.rotate").font(.system(size: 13, weight: .semibold))
                                        .padding(.horizontal, 12).frame(height: 32).background(.black.opacity(0.55), in: Capsule()).foregroundStyle(.white)
                                }
                                .padding(10)
                            }
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ПОДПИСЬ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        TextField("Что это", text: $title, axis: .vertical).font(.system(size: 18, weight: .semibold))
                            .padding(14).background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                            .disabled(!editable)
                            .onSubmit(save)
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
                    if editable {
                        Button { showMove = true } label: { Label("Переложить в другое место", systemImage: "arrow.right.square") }
                            .buttonStyle(PrimaryButtonStyle(fill: Theme.card, ink: Theme.ink))
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Удалить вещь", systemImage: "trash") }
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
            .onAppear { title = item.title }
            .task {
                if editable, let img = await PhotoStore.image(for: item, thumb: false) { suggestions = await Captioner.candidates(img) }
            }
            .confirmationDialog("Удалить вещь?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) { Task { try? await store.deleteItem(item.id); dismiss() } }
            }
            // Во весь экран, а не sheet поверх sheet'а — без «стопки окон» сзади.
            .fullScreenCover(isPresented: $showMove) {
                MoveItemView(store: store, item: item) { dismiss() }
            }
            .fullScreenCover(item: $editPhoto) { p in
                PhotoEditView(image: p.image) { edited in Task { await replacePhoto(edited) } }
            }
        }
    }

    /// Новое фото под тем же ключом: локально сразу, в R2 — следом; подсказки подписи пересчитываем.
    private func replacePhoto(_ img: UIImage) async {
        guard let data = PhotoStore.save(img, for: item.id) else { return }
        photoVersion += 1
        await PhotoStore.upload(item.id, photo: data.photo, thumb: data.thumb, store: store)
        suggestions = await Captioner.candidates(img)
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
                    ForEach(Array(store.places.enumerated()), id: \.element.id) { i, p in
                        let open = p.status == .open
                        Button { if open { selected = p.id } } label: {
                            HStack(spacing: 12) {
                                // Галочка как в «Куда едет»; текущее место отмечено с самого начала.
                                Image(systemName: selected == p.id ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22)).foregroundStyle(selected == p.id ? Theme.accent : Theme.line)
                                Image(systemName: p.kind.symbol).font(.system(size: 17, weight: .semibold))
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
                    if busy { ProgressView().tint(.white) }
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
