import SwiftUI

/// Плитка-иконка места. Для коробки — «3D» коробка с клапанами, которые закрываются при запаковке,
/// и скотчем. Остальные типы — символ на плитке; свои анимации добавим позже.
struct BoxTileView: View {
    let place: Place
    var size: CGFloat = 120

    private var packed: Bool { place.status == .packed }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(packed ? Theme.ink : Color(hex: 0xE8E6E0))
            if place.kind == .box { box } else { other }
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.55, bounce: 0.25), value: packed)
    }

    private var box: some View {
        let w = size * 0.62, h = size * 0.46, flap = h * 0.42
        return VStack(spacing: 0) {
            // клапаны: открытые стоят вертикально, при запаковке ложатся
            HStack(spacing: 2) {
                ForEach(0..<2, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(packed ? Color(hex: 0xC9A97A) : Color(hex: 0xD9B98B))
                        .frame(width: w / 2 - 1, height: flap)
                        .rotation3DEffect(.degrees(packed ? 0 : (i == 0 ? -70 : 70)),
                                          axis: (x: 0, y: 1, z: 0),
                                          anchor: i == 0 ? .leading : .trailing, perspective: 0.6)
                        .rotation3DEffect(.degrees(packed ? 0 : -35), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.5)
                }
            }
            .frame(width: w, height: flap)
            .offset(y: packed ? flap - 4 : 0)
            .zIndex(1)
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0xD9B98B))
                    .frame(width: w, height: h)
                    .overlay(alignment: .top) {
                        if packed {
                            Rectangle().fill(Theme.accent).frame(width: w * 0.22, height: h)
                                .transition(.scale(scale: 0.2, anchor: .top).combined(with: .opacity))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(place.number)
                    .font(.system(size: h * 0.62, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink.opacity(0.85)).minimumScaleFactor(0.4).lineLimit(1)
                    .padding(.horizontal, 6)
            }
        }
        .offset(y: packed ? -flap * 0.3 : flap * 0.15)
    }

    private var other: some View {
        VStack(spacing: 6) {
            Image(systemName: place.kind.symbol).font(.system(size: size * 0.26, weight: .medium))
            Text(place.number).font(.system(size: size * 0.3, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5).lineLimit(1)
        }
        .foregroundStyle(packed ? .white : Theme.ink)
        .padding(.horizontal, 8)
    }
}
