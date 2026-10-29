import SwiftUI

/// «Куда едет»: список направлений переезда, текущее отмечено «✓ выбрано»,
/// добавление нового с проверкой дубликата и лимита 5.
struct DestinationPickerView: View {
    let store: PlacesStore
    let placeId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var error: String? = nil
    @FocusState private var focused: Bool

    private var current: UUID? { store.place(placeId)?.destinationId }
    private var canAdd: Bool { store.destinations.count < AppConfig.maxDestinations }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(spacing: 0) {
                        ForEach(Array(store.destinations.enumerated()), id: \.element.id) { i, d in
                            Button {
                                Task { try? await store.updatePlace(placeId, destinationId: .some(d.id)); dismiss() }
                            } label: {
                                HStack {
                                    Text(d.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    if d.id == current {
                                        Label("выбрано", systemImage: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Theme.accent)
                                    }
                                }
                                .padding(.horizontal, 16).frame(minHeight: 56)
                                .overlay(alignment: .top) { if i > 0 { Divider().padding(.leading, 16) } }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ДОБАВИТЬ НАПРАВЛЕНИЕ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        if canAdd {
                            HStack(spacing: 8) {
                                TextField("Город и/или адрес", text: $newName).focused($focused).submitLabel(.done).onSubmit(add)
                                    .padding(.horizontal, 14).frame(height: 50)
                                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                                Button(action: add) {
                                    Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                                        .frame(width: 50, height: 50).background(Theme.ink, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
                                }
                                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                                .opacity(newName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                            }
                            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        } else {
                            Text("Максимум \(AppConfig.maxDestinations) направлений на переезд.").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Куда едет").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        Task {
            do {
                let d = try await store.addDestination(name)
                try await store.updatePlace(placeId, destinationId: .some(d.id))
                newName = ""; error = nil; dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// «Изменить коробку»: номер и тип. Фото номера — следующим шагом.
struct EditPlaceView: View {
    let store: PlacesStore
    let placeId: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var kind: PlaceKind = .box
    @State private var custom = ""
    @State private var showType = false
    @State private var error: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("НОМЕР НА КОРОБКЕ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        TextField("3, 3б, 12а…", text: $number).font(.system(size: 28, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 16).frame(height: 64)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                        if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        Text("Любой незанятый номер в этом переезде. Напишите такой же маркером на коробке.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ТИП").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        Button { showType = true } label: {
                            HStack {
                                Image(systemName: kind.symbol)
                                Text(kind == .custom ? custom : kind.title).font(.system(size: 17, weight: .semibold))
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                            }
                            .padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(Theme.ink)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Изменить место").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save).fontWeight(.bold) }
            }
            .onAppear {
                guard let p = store.place(placeId) else { return }
                number = p.number; kind = p.kind; custom = p.customKind ?? ""
            }
            .sheet(isPresented: $showType) {
                TypePickerView(selected: kind, customText: custom) { k, c in kind = k; custom = c ?? "" }
            }
        }
    }

    private func save() {
        let n = number.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { error = "Введите номер"; return }
        Task {
            do {
                try await store.updatePlace(placeId, number: n, kind: kind, customKind: .some(kind == .custom ? custom : nil))
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
