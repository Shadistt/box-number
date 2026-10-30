import SwiftUI

/// Новый переезд (ТЗ §4): Откуда + Куда 1…5, перетаскивание направлений за ≡, минус в ряду, максимум 5.
struct NewMoveView: View {
    let store: MovesStore
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var dests: [Dest] = [Dest()]
    @State private var busy = false
    @State private var error: String?

    struct Dest: Identifiable { let id = UUID(); var text = "" }

    private var filled: [String] { dests.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var cta: String {
        guard let first = filled.first else { return "Укажите, куда переезжаете" }
        let f = from.trimmingCharacters(in: .whitespaces)
        return "Начать: " + (f.isEmpty ? first : "\(f) → \(first)") + (filled.count > 1 ? " +\(filled.count - 1)" : "")
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Куда переезжаете?").font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("Коробки этого переезда будут нумероваться с 1. Название можно поменять потом.")
                    .font(.system(size: 16)).foregroundStyle(Color(hex: 0x4F5157)).padding(.top, 6)

                List {
                    field("Откуда", text: $from)
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 20, leading: 0, bottom: 4, trailing: 0))
                        .moveDisabled(true)
                    ForEach($dests) { $d in
                        let i = dests.firstIndex { $0.id == d.id } ?? 0
                        HStack(spacing: 10) {
                            Text(i == 0 ? "Куда" : "Куда \(i + 1)").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x4F5157)).frame(width: 60, alignment: .leading)
                            TextField("Город и/или адрес", text: $d.text)
                                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                                .autocorrectionDisabled().textInputAutocapitalization(.words)
                            if dests.count > 1 {
                                Button { dests.removeAll { $0.id == d.id } } label: {
                                    Image(systemName: "minus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                                        .frame(width: 36, height: 36).background(Theme.bg, in: Circle())
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.leading, 16).padding(.trailing, 8).frame(height: 58)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    }
                    .onMove { dests.move(fromOffsets: $0, toOffset: $1) }

                    if dests.count < AppConfig.maxDestinations {
                        HStack(spacing: 10) {
                                Image(systemName: "plus").font(.system(size: 15, weight: .bold))
                                Text("Ещё направление").font(.system(size: 15, weight: .semibold))
                                Spacer()
                                Text("\(dests.count) из \(AppConfig.maxDestinations)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                        .foregroundStyle(Theme.ink).padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0xB9B5AC), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.snappy) { dests.append(Dest()) } }
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .moveDisabled(true)
                    }

                    Text("Первое «Куда» даёт название переезду. Зажмите ≡ и перетащите, чтобы поменять порядок.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .listRowSeparator(.hidden).listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 4, bottom: 0, trailing: 4))
                        .moveDisabled(true)
                }
                .listStyle(.plain).scrollContentBackground(.hidden).scrollIndicators(.hidden)
                .environment(\.editMode, .constant(.active))
                .environment(\.defaultMinListRowHeight, 1)

                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.bottom, 8) }
                Button(cta) { Task { await create() } }
                    .buttonStyle(PrimaryButtonStyle(fill: filled.isEmpty ? Color(hex: 0xD5D3CC) : Theme.ink,
                                                    ink: filled.isEmpty ? Color(hex: 0x6B6D73) : .white))
                    .disabled(filled.isEmpty || busy)
            }
            .padding(.horizontal, 20).padding(.bottom, 12).background(Theme.bg)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }.foregroundStyle(Theme.ink)
                }
            }
            .toolbarBackground(Theme.bg, for: .navigationBar)
        }
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x4F5157)).frame(width: 64, alignment: .leading)
            TextField("Город и/или адрес", text: text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 16).frame(height: 58)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }

    private func create() async {
        busy = true; defer { busy = false }
        do { _ = try await store.createMove(from: from.trimmingCharacters(in: .whitespaces), to: filled); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
