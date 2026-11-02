import SwiftUI

/// 3D-сейф в стиле 3D-коробки (утверждено 03.11.2026, макет safe3d5.png): та же перспектива 140,
/// rotateX(−22°) rotateY(−32°), стальной корпус на ножках, дверца с петлями слева, объёмный кодовый диск
/// с рисками и барашком, ручка, номер на дверце.
/// `door` 0 — закрыт, 1 — дверца открыта на 70°; `dial` — поворот диска в градусах. Оба анимируются.
struct Safe3DView: View, Animatable {
    var number: String
    var door: Double = 0
    var dial: Double = 0
    var size: CGFloat = 64

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(door, dial) }
        set { door = newValue.first; dial = newValue.second }
    }

    private let W = 32.0, H = 28.0, D = 26.0
    private let perspective = 140.0
    private let rx = -22.0 * .pi / 180, ry = -32.0 * .pi / 180

    private struct V3 { var x, y, z: Double }

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64 * 0.92
            let origin = CGPoint(x: sz.width / 2, y: sz.height * 0.56)
            func P(_ v: V3) -> CGPoint { let p = project(v); return CGPoint(x: origin.x + p.x * s, y: origin.y + p.y * s) }
            func fill(_ pts: [CGPoint], _ hex: UInt32) {
                var p = Path(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: hex)))
            }
            let L = -W/2, R = W/2, T = -H/2, B = H/2, F = D/2, K = -D/2

            // корпус: грани по глубине, дальние первыми
            var faces: [([V3], UInt32)] = [
                ([V3(x: L, y: T, z: K), V3(x: R, y: T, z: K), V3(x: R, y: T, z: F), V3(x: L, y: T, z: F)], 0x7A8089),  // верх
                ([V3(x: R, y: T, z: F), V3(x: R, y: T, z: K), V3(x: R, y: B, z: K), V3(x: R, y: B, z: F)], 0x4B5058),  // правая
                ([V3(x: L, y: T, z: K), V3(x: L, y: T, z: F), V3(x: L, y: B, z: F), V3(x: L, y: B, z: K)], 0x454A51),  // левая
                ([V3(x: L, y: T, z: F), V3(x: R, y: T, z: F), V3(x: R, y: B, z: F), V3(x: L, y: B, z: F)], 0x5E646C),  // передняя рама
            ]
            for fx in [L + 2.5, R - 5.5] {   // ножки
                faces.append(([V3(x: fx, y: B, z: F - 2), V3(x: fx + 3, y: B, z: F - 2), V3(x: fx + 3, y: B + 2.2, z: F - 2), V3(x: fx, y: B + 2.2, z: F - 2)], 0x2A2D32))
            }
            faces.sort { depth($0.0) < depth($1.0) }
            for f in faces { fill(f.0.map(P), f.1) }

            // дверца: поворот вокруг левой кромки; h — высота над плоскостью двери (нормаль поворачивается вместе с ней)
            let m = 2.4, dl = L + m, dr = R - m, dt = T + m, db = B - m
            let ang = door * 70 * .pi / 180
            func DP(_ px: Double, _ py: Double, _ h: Double = 0) -> CGPoint {
                let lx = px - dl
                return P(V3(x: dl + lx * cos(ang) - h * sin(ang), y: py, z: F + 0.6 + lx * sin(ang) + h * cos(ang)))
            }
            if door > 0.001 {   // тёмный проём
                fill([V3(x: dl, y: dt, z: F + 0.1), V3(x: dr, y: dt, z: F + 0.1), V3(x: dr, y: db, z: F + 0.1), V3(x: dl, y: db, z: F + 0.1)].map(P), 0x1E2024)
            }
            let b = 1.3
            fill([DP(dl, dt), DP(dr, dt), DP(dr, db), DP(dl, db)], 0x6B717A)
            fill([DP(dl + b, dt + b), DP(dr - b, dt + b), DP(dr - b, db - b), DP(dl + b, db - b)], 0x737983)
            fill([DP(dl, dt), DP(dr, dt), DP(dr - b, dt + b), DP(dl + b, dt + b)], 0x8C939C)   // блик сверху
            fill([DP(dl, db), DP(dr, db), DP(dr - b, db - b), DP(dl + b, db - b)], 0x4F545B)   // тень снизу
            for hy in [dt + 3.5, db - 6] {   // петли
                fill([DP(dl - 0.9, hy), DP(dl + 0.6, hy), DP(dl + 0.6, hy + 2.5), DP(dl - 0.9, hy + 2.5)], 0x2E3136)
            }

            let cx = dr - 7.2, cy = -0.6
            // номер слева на дверце — до диска, чтобы длинный номер не перекрывал его
            let a = DP(dl + b, dt + b), bx = DP(dl + b + 1, dt + b), cyP = DP(dl + b, dt + b + 1)
            let toCanvas = CGAffineTransform(a: bx.x - a.x, b: bx.y - a.y, c: cyP.x - a.x, d: cyP.y - a.y, tx: a.x, ty: a.y)
            let fs: CGFloat = number.count > 2 ? 5.6 : 8
            let tx = ((dl + b + 2.2) + (cx - 5.8)) / 2 - (dl + b)
            ctx.drawLayer { layer in
                layer.transform = toCanvas
                let text = Text(number).font(.system(size: fs, weight: .black, design: .rounded)).foregroundStyle(Color(hex: 0xEEF0F3))
                layer.draw(text, at: CGPoint(x: tx, y: (db - dt - 2 * b) / 2), anchor: .center)
            }

            // объёмный кодовый диск: основание, барабан с рисками, ручка с барашком
            let rot = dial * .pi / 180
            func cylinder(_ r: Double, _ h0: Double, _ h1: Double, side: UInt32, top: UInt32, n: Int = 40) {
                let pts = (0..<n).map { i -> (Double, Double) in let t = 2 * Double.pi * Double(i) / Double(n); return (cx + r * cos(t), cy + r * sin(t)) }
                for i in 0..<n {
                    let p = pts[i], q = pts[(i + 1) % n]
                    var path = Path()
                    path.addLines([DP(p.0, p.1, h0), DP(q.0, q.1, h0), DP(q.0, q.1, h1), DP(p.0, p.1, h1)]); path.closeSubpath()
                    ctx.fill(path, with: .color(Color(hex: side)))
                    ctx.stroke(path, with: .color(Color(hex: side)), lineWidth: 0.3)
                }
                fill(pts.map { DP($0.0, $0.1, h1) }, top)
            }
            func line(_ p1: CGPoint, _ p2: CGPoint, _ hex: UInt32, _ w: CGFloat) {
                var p = Path(); p.move(to: p1); p.addLine(to: p2)
                ctx.stroke(p, with: .color(Color(hex: hex)), style: StrokeStyle(lineWidth: w, lineCap: .round))
            }
            cylinder(5.6, 0, 0.5, side: 0x2E3136, top: 0x3A3E44)
            cylinder(4.7, 0.5, 2.0, side: 0x9AA0A8, top: 0xD9DDE3)
            for i in 0..<16 {   // риски крутятся вместе с барабаном
                let t = 2 * Double.pi * Double(i) / 16 + rot
                let r1 = i % 4 == 0 ? 3.3 : 3.8, r2 = 4.5
                line(DP(cx + r1 * cos(t), cy + r1 * sin(t), 2), DP(cx + r2 * cos(t), cy + r2 * sin(t), 2), 0x6E747C, (i % 4 == 0 ? 0.45 : 0.3) * s)
            }
            // неподвижная метка над диском
            ctx.stroke({ var p = Path(); p.move(to: DP(cx, cy - 6.3, 0.6)); p.addLine(to: DP(cx, cy - 5.5, 0.6)); return p }(),
                       with: .color(Theme.accent), style: StrokeStyle(lineWidth: 0.7 * s, lineCap: .round))
            cylinder(2.4, 2.0, 3.6, side: 0x7E848C, top: 0xB4BAC2, n: 32)
            let wa = rot - .pi / 2, ca = cos(wa), sa = sin(wa)
            func W3(_ u: Double, _ v: Double, _ h: Double) -> CGPoint { DP(cx + u * ca - v * sa, cy + u * sa + v * ca, h) }
            let wing: [(Double, Double)] = [(-2.2, -0.55), (2.2, -0.55), (2.2, 0.55), (-2.2, 0.55)]
            for i in 0..<4 {
                let p = wing[i], q = wing[(i + 1) % 4]
                fill([W3(p.0, p.1, 3.6), W3(q.0, q.1, 3.6), W3(q.0, q.1, 4.6), W3(p.0, p.1, 4.6)], 0x5A6068)
            }
            fill(wing.map { W3($0.0, $0.1, 4.6) }, 0x8A9099)
            // ручка двери — объёмный брусок
            let hx0 = cx - 4.2, hx1 = cx + 2.2, hy0 = cy + 6.2, hy1 = cy + 7.6, hh = 1.6
            fill([DP(hx0, hy0), DP(hx1, hy0), DP(hx1, hy0, hh), DP(hx0, hy0, hh)], 0x8E949C)
            fill([DP(hx0, hy0), DP(hx0, hy1), DP(hx0, hy1, hh), DP(hx0, hy0, hh)], 0x8E949C)
            fill([DP(hx1, hy0), DP(hx1, hy1), DP(hx1, hy1, hh), DP(hx1, hy0, hh)], 0x8E949C)
            fill([DP(hx0, hy0, hh), DP(hx1, hy0, hh), DP(hx1, hy1, hh), DP(hx0, hy1, hh)], 0xDDE1E6)
        }
        .frame(width: size, height: size)
    }

    private func rotate(_ v: V3) -> V3 {
        let cy = cos(ry), sy = sin(ry)
        let x1 = v.x * cy + v.z * sy, z1 = -v.x * sy + v.z * cy
        let cx = cos(rx), sx = sin(rx)
        let y2 = v.y * cx - z1 * sx, z2 = v.y * sx + z1 * cx
        return V3(x: x1, y: y2, z: z2)
    }
    private func project(_ v: V3) -> CGPoint {
        let r = rotate(v)
        let k = perspective / (perspective - r.z)
        let oy = -0.15 * 64 / 0.92
        return CGPoint(x: r.x * k, y: oy + (r.y - oy) * k)
    }
    private func depth(_ pts: [V3]) -> Double { pts.map { rotate($0).z }.reduce(0, +) / Double(pts.count) }
}

/// Сейф, который сам открывается и закрывается вместе с SafeSession:
/// открыли паролем или Face ID — диск «набирает код» (вправо, назад, вправо), щелчок, дверца приоткрывается.
struct LiveSafe3DView: View {
    var number: String
    var size: CGFloat = 64
    @State private var safe = SafeSession.shared
    @State private var door: Double = 0
    @State private var dial: Double = 0

    var body: some View {
        Safe3DView(number: number, door: door, dial: dial, size: size)
            .onAppear { door = safe.isOpen ? 0.5 : 0; dial = safe.isOpen ? 220 : 0 }
            .onChange(of: safe.isOpen) { _, open in
                if open {
                    withAnimation(.easeInOut(duration: 0.45)) { dial = 300 }
                    withAnimation(.easeInOut(duration: 0.4).delay(0.45)) { dial = 100 }
                    withAnimation(.easeInOut(duration: 0.35).delay(0.85)) { dial = 220 }
                    withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(1.3)) { door = 0.5 }
                } else {
                    withAnimation(.easeInOut(duration: 0.35)) { door = 0 }
                    withAnimation(.easeInOut(duration: 0.5).delay(0.3)) { dial = 0 }
                }
            }
    }
}
