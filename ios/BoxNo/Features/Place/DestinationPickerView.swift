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
                                HStack(spacing: 12) {
                                    // Системная «радиоточка»: выбранное — закрашенный круг с галочкой.
                                    Image(systemName: d.id == current ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22)).foregroundStyle(d.id == current ? Theme.accent : Theme.line)
                                    Text(d.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                                    Spacer()
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
                                        .frame(width: 50, height: 50).background(Theme.ink, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(Theme.onInk)
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
                // Новое направление только появляется в списке — выбрать и закрыть пользователь решает сам.
                _ = try await store.addDestination(name)
                newName = ""; error = nil
            } catch { self.error = error.localizedDescription }
        }
    }
}
