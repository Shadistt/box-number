import SwiftUI

/// Плашка статуса места, вариант B (ТЗ §7).
/// Свёрнута: слева «Едет в …» со стрелкой и статус, справа круглая кнопка-замок.
/// Раскрыта: «Куда едет?» и чипы направлений, кнопки нет.
/// Без направления: раскрыта, белая с оранжевой рамкой, свернуть нельзя, замка нет.
struct StatusBarView: View {
    let place: Place
    let destinations: [MoveDestination]
    let itemsCount: Int
    let takenCount: Int
    @Binding var expanded: Bool
    let onSelect: (MoveDestination) -> Void
    let onLock: () -> Void

    private var needDest: Bool { place.destinationId == nil }
    private var isOpen: Bool { expanded || needDest }
    private var packed: Bool { place.status == .packed }
    private var destName: String { destinations.first { $0.id == place.destinationId }?.name ?? "" }

    private var bg: Color { packed ? Theme.ink : .white }
    private var ink: Color { packed ? .white : Theme.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    guard !needDest else { return }
                    withAnimation(.snappy) { expanded.toggle() }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(isOpen ? "Куда едет?" : "Едет в \(destName)")
                                .font(.system(size: 17, weight: .bold)).lineLimit(1).truncationMode(.tail)
                            if !needDest {
                                Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold))
                                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                            }
                        }
                        Text(statusText).font(.subheadline).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if !isOpen {
                    Button(action: onLock) {
                        Image(systemName: packed ? "lock.fill" : "lock.open")
                            .font(.system(size: 18, weight: .bold))
                            .frame(width: 44, height: 44)
                            .background(packed ? Theme.accent : Theme.ink, in: Circle())
                            .foregroundStyle(packed ? Theme.ink : .white)
                    }
                    .accessibilityLabel(packed ? "Распаковать" : "Запаковать")
                    .transition(.scale.combined(with: .opacity))
                }
            }

            if isOpen {
                FlowLayout(spacing: 8) {
                    ForEach(destinations) { d in
                        let on = d.id == place.destinationId
                        Button {
                            onSelect(d)
                            withAnimation(.snappy) { expanded = false }
                        } label: {
                            HStack(spacing: 6) {
                                if on { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)) }
                                Text(d.name).lineLimit(1).truncationMode(.tail)
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14).frame(height: 36).frame(maxWidth: 170)
                            .background(on ? Theme.accent : Theme.bg, in: Capsule())
                            .foregroundStyle(Theme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .background(isOpen && !packed ? .white : bg, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            if needDest { RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.accent, lineWidth: 1.5) }
        }
        .foregroundStyle(isOpen && !packed ? Theme.ink : ink)
    }

    private var statusText: String {
        if needDest { return "Выберите направление, чтобы запаковать" }
        switch place.status {
        case .open: return "Открыта · " + Plural.things(itemsCount)
        case .packed:
            let d = place.packedAt?.formatted(.dateTime.day().month(.wide)) ?? ""
            return "Запакована \(d) · " + Plural.things(itemsCount)
        case .unpacking: return "Распаковка · достали \(takenCount) из \(itemsCount)"
        }
    }
}

/// Простая раскладка «в строку с переносом» для чипов.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height)
        }
    }
}
