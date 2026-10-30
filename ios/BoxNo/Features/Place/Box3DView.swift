import SwiftUI

/// 3D-коробка как в макете (BoxNew.dc.html): перспектива 140, rotateX(−22°) rotateY(−32°),
/// грани 34×26×26, четыре клапана, открытые на 112°, при запаковке — скотч.
/// `openness` 1 — открыта, 0 — закрыта; анимируется.
struct Box3DView: View, Animatable {
    var number: String
    var openness: Double
    var size: CGFloat = 64

    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }

    // геометрия в «пикселях макета» (плитка 64)
    private let w = 34.0, h = 26.0, d = 26.0
    private let perspective = 140.0
    private let rx = -22.0 * .pi / 180, ry = -32.0 * .pi / 180

    private struct V3 { var x, y, z: Double }
    private struct Face { var pts: [CGPoint]; var depth: Double; var color: Color; var opacity: Double = 1 }

    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 64 * 0.92
            let origin = CGPoint(x: sz.width / 2, y: sz.height * 0.56)
            var faces = buildFaces()
            faces.sort { $0.depth < $1.depth }       // дальние первыми
            for f in faces {
                var p = Path()
                let pts = f.pts.map { CGPoint(x: origin.x + $0.x * s, y: origin.y + $0.y * s) }
                p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }; p.closeSubpath()
                ctx.fill(p, with: .color(f.color.opacity(f.opacity)))
            }
            // номер на передней грани: аффинное приближение проекции
            let front = project(frontQuad())
            let a = front[0], b = front[1], c = front[3]      // верх-лево, верх-право, низ-лево
            let ux = CGPoint(x: (b.x - a.x) / w, y: (b.y - a.y) / w)
            let uy = CGPoint(x: (c.x - a.x) / h, y: (c.y - a.y) / h)
            // сначала в систему грани, затем масштаб и сдвиг холста
            let faceToCanvas = CGAffineTransform(a: ux.x, b: ux.y, c: uy.x, d: uy.y, tx: a.x, ty: a.y)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: origin.x, y: origin.y))
            ctx.drawLayer { layer in
                layer.transform = faceToCanvas
                let text = Text(number).font(.custom("PermanentMarker-Regular", size: 17)).foregroundStyle(Color(hex: 0x1B1A18))
                layer.draw(text, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: 3D → 2D

    private func rotate(_ v: V3) -> V3 {
        // CSS: rotateX(-22) rotateY(-32) → точка сначала поворачивается вокруг Y, потом вокруг X
        let cy = cos(ry), sy = sin(ry)
        let x1 = v.x * cy + v.z * sy, z1 = -v.x * sy + v.z * cy
        let cx = cos(rx), sx = sin(rx)
        let y2 = v.y * cx - z1 * sx, z2 = v.y * sx + z1 * cx
        return V3(x: x1, y: y2, z: z2)
    }

    private func project(_ pts: [V3]) -> [CGPoint] {
        pts.map { p in
            let r = rotate(p)
            // perspective-origin 50% 35%: центр схода чуть выше центра плитки
            let k = perspective / (perspective - r.z)
            let oy = -0.15 * 64 / 0.92   // смещение точки схода (35% вместо 50%)
            return CGPoint(x: r.x * k, y: oy + (r.y - oy) * k)
        }
    }

    private func depth(_ pts: [V3]) -> Double { pts.map { rotate($0).z }.reduce(0, +) / Double(pts.count) }

    private func frontQuad() -> [V3] {
        [V3(x: -w/2, y: -h/2, z: d/2), V3(x: w/2, y: -h/2, z: d/2), V3(x: w/2, y: h/2, z: d/2), V3(x: -w/2, y: h/2, z: d/2)]
    }

    private func buildFaces() -> [Face] {
        func face(_ pts: [V3], _ color: Color, _ opacity: Double = 1) -> Face {
            Face(pts: project(pts), depth: depth(pts), color: color, opacity: opacity)
        }
        let L = -w/2, R = w/2, T = -h/2, B = h/2, F = d/2, K = -d/2
        var faces: [Face] = [
            face([V3(x: L, y: B, z: K), V3(x: R, y: B, z: K), V3(x: R, y: B, z: F), V3(x: L, y: B, z: F)], Color(hex: 0x4A3B2F)),  // дно
            face([V3(x: R, y: T, z: K), V3(x: L, y: T, z: K), V3(x: L, y: B, z: K), V3(x: R, y: B, z: K)], Color(hex: 0xB58E66)),  // задняя
            face([V3(x: L, y: T, z: K), V3(x: L, y: T, z: F), V3(x: L, y: B, z: F), V3(x: L, y: B, z: K)], Color(hex: 0xA07A55)),  // левая
            face([V3(x: R, y: T, z: F), V3(x: R, y: T, z: K), V3(x: R, y: B, z: K), V3(x: R, y: B, z: F)], Color(hex: 0xAD8560)),  // правая
            face(frontQuad(), Color(hex: 0xCDA67F)),                                                                             // передняя
        ]
        // клапаны: шарнир на кромке верха, угол 0 (закрыт, лежит в плоскости верха) … 112° (открыт, наружу)
        let ang = openness * 112.0 * .pi / 180
        func flap(hingeA: V3, hingeB: V3, inward: V3, length: Double, color: Color) -> Face {
            // точка клапана = шарнир + inward*t (в плоскости верха, к центру) повёрнутая наружу на ang вокруг шарнира
            // при повороте «вверх-наружу»: вектор inward переходит в cos·inward + sin·(вверх), затем за 90° — в outward
            let up = V3(x: 0, y: -1, z: 0)
            func rot(_ t: Double, _ base: V3) -> V3 {
                let c = cos(ang), s = sin(ang)
                // в плоскости (inward, up): inward → inward·c + up·s; за пределами 90° (c<0) клапан уходит наружу (−inward)
                return V3(x: base.x + t * (inward.x * c + up.x * s), y: base.y + t * (inward.y * c + up.y * s), z: base.z + t * (inward.z * c + up.z * s))
            }
            let pts = [hingeA, hingeB, rot(length, hingeB), rot(length, hingeA)]
            return face(pts, color)
        }
        let top = T
        // задний (fb): шарнир по задней кромке, длина 13 к центру
        faces.append(flap(hingeA: V3(x: L, y: top, z: K), hingeB: V3(x: R, y: top, z: K), inward: V3(x: 0, y: 0, z: 1), length: 13, color: Color(hex: 0xD6B58F)))
        // передний (ff)
        faces.append(flap(hingeA: V3(x: R, y: top, z: F), hingeB: V3(x: L, y: top, z: F), inward: V3(x: 0, y: 0, z: -1), length: 13, color: Color(hex: 0xDDBE9A)))
        // левый (fl) и правый (fr): длина 17
        faces.append(flap(hingeA: V3(x: L, y: top, z: F), hingeB: V3(x: L, y: top, z: K), inward: V3(x: 1, y: 0, z: 0), length: 17, color: Color(hex: 0xE2C6A4)))
        faces.append(flap(hingeA: V3(x: R, y: top, z: K), hingeB: V3(x: R, y: top, z: F), inward: V3(x: -1, y: 0, z: 0), length: 17, color: Color(hex: 0xE2C6A4)))
        // скотч по центру верха — виден, когда закрыто
        if openness < 0.35 {
            let tape = [V3(x: -1.5, y: top - 0.3, z: K), V3(x: 1.5, y: top - 0.3, z: K), V3(x: 1.5, y: top - 0.3, z: F), V3(x: -1.5, y: top - 0.3, z: F)]
            faces.append(face(tape, Theme.accent, 1 - openness / 0.35))
        }
        return faces
    }
}
