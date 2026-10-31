import SwiftUI

/// Новый переезд (ТЗ §4): Откуда + Куда 1…5, перетаскивание направлений за ≡, минус в ряду, максимум 5.
struct NewMoveView: View {
    let store: MovesStore
    var onCreated: ((Move) -> Void)? = nil      // главный открывает новый переезд сразу после создания
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var dests: [Dest] = [Dest()]
    @State private var busy = false
    @State private var error: String?
    // Перетаскивание направления за ≡: ряд «поднимается» (тень, чуть крупнее), соседи плавно разъезжаются
    // (паттерн Luma / Klarna «Reorder» с Mobbin).
    @State private var dragging: UUID?
    @State private var dragOffset: CGFloat = 0
    @FocusState private var focusedDest: UUID?
    private let rowStep: CGFloat = 58 + 8

    struct Dest: Identifiable { let id = UUID(); var text = "" }

    private var filled: [String] { dests.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    /// Единая надпись: длинные названия городов на кнопке выглядели плохо.
    private var cta: String { filled.isEmpty ? "Укажите, куда переезжаете" : "Начать переезд" }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("Куда переезжаете?").font(.system(size: 30, weight: .heavy)).foregroundStyle(Theme.ink)
                Text("Коробки этого переезда будут нумероваться с 1. Название можно поменять потом.")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted).padding(.top, 6)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        field("Откуда", text: $from).padding(.top, 20)
                        ForEach(dests) { d in
                            let i = dests.firstIndex { $0.id == d.id } ?? 0
                            destRow(d, index: i)
                        }
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
                            .onTapGesture {
                                let d = Dest()
                                withAnimation(.snappy) { dests.append(d) }
                                focusedDest = d.id   // курсор сразу в новое поле, клавиатура открыта
                            }
                        }
                        Text("Первое «Куда» даёт название переезду. Зажмите ≡ и перетащите, чтобы поменять порядок.")
                            .font(.system(size: 13)).foregroundStyle(Theme.muted).padding(.horizontal, 4).padding(.top, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .scrollDisabled(dragging != nil)

                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.bottom, 8) }
                Button(cta) { Task { await create() } }
                    .buttonStyle(PrimaryButtonStyle(fill: filled.isEmpty ? Color(hex: 0xD5D3CC) : Theme.ink,
                                                    ink: filled.isEmpty ? Theme.muted : Theme.onInk))
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

    private func destRow(_ d: Dest, index i: Int) -> some View {
        let lifted = dragging == d.id
        let binding = Binding(get: { dests.first { $0.id == d.id }?.text ?? "" },
                              set: { v in if let k = dests.firstIndex(where: { $0.id == d.id }) { dests[k].text = v } })
        return HStack(spacing: 12) {
            Text(i == 0 ? "Куда" : "Куда \(i + 1)").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)   // как у «Откуда» — текст в одну линию
            TextField("Город и/или адрес", text: binding).focused($focusedDest, equals: d.id)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
            if dests.count > 1 {
                Button { withAnimation(.snappy) { dests.removeAll { $0.id == d.id } } } label: {
                    Image(systemName: "minus").font(.system(size: 13, weight: .heavy)).foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36).background(Theme.bg, in: Circle())
                }.buttonStyle(.plain)
                Image(systemName: "line.3.horizontal").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(lifted ? Theme.ink : Color(hex: 0xB9B5AC))
                    .frame(width: 36, height: 58).contentShape(Rectangle())
                    .gesture(dragGesture(d.id))
            }
        }
        .padding(.leading, 16).padding(.trailing, 8).frame(height: 58)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .scaleEffect(lifted ? 1.03 : 1)
        .shadow(color: .black.opacity(lifted ? 0.18 : 0), radius: lifted ? 14 : 0, y: lifted ? 6 : 0)
        .offset(y: lifted ? dragOffset : shift(i))
        .zIndex(lifted ? 1 : 0)
    }

    /// Во время перетаскивания массив не меняется: поднятый ряд идёт за пальцем, соседи сдвигаются на высоту ряда,
    /// когда он их «проходит». Перестановка в массиве — в момент отпускания, без анимации (позиции уже совпадают).
    private func dragGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                guard let start = dests.firstIndex(where: { $0.id == id }) else { return }
                if dragging == nil {
                    withAnimation(.snappy(duration: 0.2)) { dragging = id }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                dragOffset = v.translation.height
                let target = min(max(start + Int((v.translation.height / rowStep).rounded()), 0), dests.count - 1)
                if target != dropIndex {
                    withAnimation(.snappy(duration: 0.25)) { dropIndex = target }
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            }
            .onEnded { v in
                guard let start = dests.firstIndex(where: { $0.id == id }) else { return }
                let target = dropIndex ?? start
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) {
                    dests.move(fromOffsets: IndexSet(integer: start), toOffset: target > start ? target + 1 : target)
                    dragOffset = v.translation.height + CGFloat(start - target) * rowStep   // визуально там же, где палец
                    dropIndex = nil
                }
                withAnimation(.snappy(duration: 0.25)) { dragOffset = 0; dragging = nil }
            }
    }

    @State private var dropIndex: Int?
    /// Сдвиг соседа: ряды между старым и новым местом поднятого ряда уступают ему место.
    private func shift(_ index: Int) -> CGFloat {
        guard let dragging, let start = dests.firstIndex(where: { $0.id == dragging }), let target = dropIndex, index != start else { return 0 }
        if start < index && index <= target { return -rowStep }
        if target <= index && index < start { return rowStep }
        return 0
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).frame(width: 64, alignment: .leading)
            TextField("Город и/или адрес", text: text).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
        }
        .padding(.horizontal, 16).frame(height: 58)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func create() async {
        busy = true; defer { busy = false }
        do { let m = try await store.createMove(from: from.trimmingCharacters(in: .whitespaces), to: filled); onCreated?(m); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}
