import SwiftUI

/// Плитка-иконка места. Для коробки — «3D» коробка с клапанами, которые закрываются при запаковке,
/// и скотчем. Остальные типы — символ на плитке; свои анимации добавим позже.
struct BoxTileView: View {
    let place: Place
    var size: CGFloat = 120
    /// Карандаш в углу (вариант A, 02.11.2026): «нажмите, чтобы изменить место». Только на экране места и только с правом edit.
    var editHint = false
    @State private var photo: UIImage? = nil
    @State private var changes = PhotoStore.Changes.shared

    private var packed: Bool { place.status == .packed }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(packed ? Theme.dark : Theme.tile)
            if let photo {
                // Фото самого места; номер — бейджем в углу, чтобы оставался виден.
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.18))
                    .overlay(alignment: .topLeading) {
                        Text(place.number).font(.system(size: size * 0.16, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(packed ? Theme.dark : Theme.card, in: Capsule())
                            .foregroundStyle(packed ? Theme.onInk : Theme.ink).padding(6)
                    }
            } else if place.kind == .box { Box3DView(number: place.number, openness: packed ? 0 : 1, size: size) } else { other }
        }
        .frame(width: size, height: size)
        // Пометки §13 в сетке: бейдж в правом верхнем углу (на экране места они чипами в шапке).
        .overlay(alignment: .topTrailing) {
            if !editHint && (place.isFragile || place.opensFirst) {
                HStack(spacing: 3) {
                    if place.opensFirst { Image(systemName: "1.circle.fill") }
                    if place.isFragile { Image(systemName: "wineglass.fill") }
                }
                .font(.system(size: max(11, size * 0.1), weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 6).frame(height: max(20, size * 0.17))
                .background(Theme.accent, in: Capsule()).padding(5)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if editHint {
                // Как Spotify / Alta «Edit profile»: круглый карандаш с обводкой цвета фона.
                Image(systemName: "pencil").font(.system(size: size * 0.13, weight: .bold))
                    .frame(width: size * 0.28, height: size * 0.28)
                    .background(packed ? Theme.card : Theme.ink, in: Circle())
                    .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                    .foregroundStyle(packed ? Theme.dark : Theme.onInk)
                    .offset(x: 6, y: 6)
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.25), value: packed)
        .task(id: "\(place.numberPhoto ?? "")-\(changes.version)") {   // при пересъёмке ключ тот же — обновляемся по счётчику замен
            photo = place.numberPhoto == nil ? nil : await PhotoStore.image(forPlace: place, thumb: size <= 160)
        }
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
        .foregroundStyle(packed ? Theme.onInk : Theme.ink)
        .padding(.horizontal, 8)
    }
}
