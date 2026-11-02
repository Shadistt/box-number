import SwiftUI

/// Значок типа места. Для сейфа (02.11.2026, отзыв «нужна иконка сейфа с кодовым замком, а не еле заметный замок»)
/// своя картинка: корпус сейфа, дверца, кодовый диск и ручка; остальные типы — SF Symbols.
struct KindIcon: View {
    let kind: PlaceKind
    var size: CGFloat = 17
    var weight: Font.Weight = .semibold

    var body: some View {
        if kind.isSafe {
            SafeGlyph(lineWidth: size * (weight == .medium ? 0.085 : 0.1)).frame(width: size * 1.2, height: size * 1.2)
        } else {
            Image(systemName: kind.symbol).font(.system(size: size, weight: weight))
        }
    }
}

/// Сейф: рамка корпуса, дверца, диск с рисками, ручка справа, ножки. Цвет — текущий foregroundStyle.
struct SafeGlyph: View {
    var lineWidth: CGFloat = 2
    var body: some View {
        GeometryReader { g in
            let s = min(g.size.width, g.size.height)
            let lw = lineWidth
            let bodyH = s * 0.86
            ZStack(alignment: .topLeading) {
                // корпус
                RoundedRectangle(cornerRadius: s * 0.14).stroke(lineWidth: lw)
                    .frame(width: s, height: bodyH)
                // дверца
                RoundedRectangle(cornerRadius: s * 0.07).stroke(lineWidth: lw * 0.7)
                    .frame(width: s * 0.72, height: bodyH * 0.72)
                    .offset(x: s * 0.1, y: bodyH * 0.14)
                // кодовый диск
                Circle().stroke(lineWidth: lw)
                    .frame(width: s * 0.34, height: s * 0.34)
                    .offset(x: s * 0.29, y: bodyH * 0.5 - s * 0.17)
                Circle().frame(width: lw * 1.3, height: lw * 1.3)
                    .offset(x: s * 0.46 - lw * 0.65, y: bodyH * 0.5 - lw * 0.65)
                // риски диска
                ForEach(0..<4) { i in
                    Capsule().frame(width: lw * 0.7, height: s * 0.06)
                        .offset(y: -s * 0.215)
                        .rotationEffect(.degrees(Double(i) * 90))
                        .position(x: s * 0.46, y: bodyH * 0.5)
                }
                // ручка
                Capsule().frame(width: lw * 1.1, height: bodyH * 0.26)
                    .offset(x: s * 0.89 - lw * 0.55, y: bodyH * 0.37)
                // ножки
                Capsule().frame(width: s * 0.16, height: lw * 1.2).offset(x: s * 0.12, y: bodyH + lw * 0.4)
                Capsule().frame(width: s * 0.16, height: lw * 1.2).offset(x: s * 0.72, y: bodyH + lw * 0.4)
            }
            .frame(width: s, height: s, alignment: .topLeading)
            .frame(width: g.size.width, height: g.size.height)
        }
    }
}
