import SwiftUI

/// Тип места: сетка из 8 карточек. «Свой вариант» раскрывает поле ввода.
struct TypePickerView: View {
    var selected: PlaceKind? = nil
    var customText: String = ""
    let onPick: (PlaceKind, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @State private var showCustom = false
    @FocusState private var customFocused: Bool

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PlaceKind.allCases) { kind in
                        Button {
                            if kind == .custom { withAnimation(.snappy) { showCustom = true }; customFocused = true }
                            else { onPick(kind, nil); dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Image(systemName: kind.symbol).font(.system(size: 30, weight: .medium))
                                    .frame(height: 40)
                                Spacer(minLength: 0)
                                Text(kind.title).font(.system(size: 16, weight: .bold))
                                    .multilineTextAlignment(.leading).lineLimit(2)
                            }
                            .padding(16).frame(maxWidth: .infinity, minHeight: 124, alignment: .leading)
                            .background(selected == kind ? Theme.ink : Theme.card, in: RoundedRectangle(cornerRadius: 20))
                            .foregroundStyle(selected == kind ? Theme.onInk : Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)

                if showCustom {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("КАК НАЗЫВАЕТСЯ").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
                        TextField("Велосипед, лампа, кресло…", text: $custom)
                            .focused($customFocused).submitLabel(.done)
                            .onSubmit(pickCustom)
                            .padding(.horizontal, 16).frame(height: 52)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                        Button("Добавить место", action: pickCustom)
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                            .opacity(custom.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Theme.bg)
            .navigationTitle("Тип места").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
            .onAppear { custom = customText; showCustom = selected == .custom }
        }
    }

    private func pickCustom() {
        let t = custom.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        onPick(.custom, t); dismiss()
    }
}
