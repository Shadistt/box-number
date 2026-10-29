import SwiftUI

/// Новый переезд: Откуда + Куда 1…5, перетаскивание направлений.
struct NewMoveView: View {
    let store: MovesStore
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to: [String] = [""]
    @State private var busy = false
    @State private var error: String?

    private var filled: [String] { to.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var title: String { (from.isEmpty ? "" : "\(from) → ") + (filled.first ?? "") + (filled.count > 1 ? " +\(filled.count - 1)" : "") }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Куда переезжаете?").font(.system(size: 30, weight: .heavy))
                Text("Коробки этого переезда будут нумероваться с 1. Название можно поменять потом.").foregroundStyle(Theme.muted)

                List {
                    row("Откуда", text: $from)
                    ForEach(to.indices, id: \.self) { i in
                        row(i == 0 ? "Куда" : "Куда \(i + 1)", text: $to[i])
                    }
                    .onMove { to.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { if to.count > 1 { to.remove(atOffsets: $0) } }
                    if to.count < AppConfig.maxDestinations {
                        Button { to.append("") } label: {
                            Label("Ещё направление", systemImage: "plus").foregroundStyle(Theme.ink)
                        }
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))

                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button(filled.isEmpty ? "Укажите, куда переезжаете" : "Начать: \(title)") { Task { await create() } }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(filled.isEmpty || busy).opacity(filled.isEmpty ? 0.4 : 1)
            }
            .padding(20).background(Theme.bg)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } } }
        }
    }

    private func row(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)
            TextField("Город и/или адрес", text: text).font(.system(size: 17, weight: .semibold))
        }
        .padding(.horizontal, 16).frame(height: 58)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private func create() async {
        busy = true; defer { busy = false }
        do { _ = try await store.createMove(from: from, to: filled); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
