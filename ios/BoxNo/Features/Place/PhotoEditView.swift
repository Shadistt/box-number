import SwiftUI

/// Правка фото вещи: приблизить/сдвинуть (щипок и перетаскивание) внутри квадратной рамки и повернуть на 90°.
/// Паттерн Feeld / Binance «Edit picture» (Mobbin): тёмный фон, рамка по центру, поворот снизу, Отмена / Готово.
struct PhotoEditView: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var offsetStart: CGSize = .zero
    @State private var quarterTurns = 0          // поворот по 90°

    var body: some View {
        GeometryReader { g in
            let frame = min(g.size.width, g.size.height * 0.6) - 32
            VStack(spacing: 0) {
                HStack {
                    Button("Отмена") { dismiss() }.foregroundStyle(.white)
                    Spacer()
                    Text("Фото").font(.headline).foregroundStyle(.white)
                    Spacer()
                    Button("Готово") { onDone(render(frame: frame)); dismiss() }.font(.headline).foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 20).padding(.top, 12).frame(height: 56)

                Spacer()
                ZStack {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: frame, height: frame)
                        .rotationEffect(.degrees(Double(quarterTurns) * 90))
                        .scaleEffect(zoom)
                        .offset(offset)
                        .animation(.snappy, value: quarterTurns)
                    // затемнение вокруг рамки
                    Rectangle().fill(.black.opacity(0.55))
                        .mask { Rectangle().overlay { Rectangle().frame(width: frame, height: frame).blendMode(.destinationOut) }.compositingGroup() }
                        .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: 1.5).frame(width: frame, height: frame).allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(SimultaneousGesture(
                    MagnifyGesture().onChanged { v in zoom = min(max(zoomStart * v.magnification, 1), 6) }
                        .onEnded { _ in zoomStart = zoom; withAnimation(.snappy) { clamp(frame: frame) } },
                    DragGesture().onChanged { v in offset = CGSize(width: offsetStart.width + v.translation.width, height: offsetStart.height + v.translation.height) }
                        .onEnded { _ in withAnimation(.snappy) { clamp(frame: frame) }; offsetStart = offset }
                ))
                Spacer()

                HStack(spacing: 40) {
                    rotateButton("rotate.left", -1)
                    rotateButton("rotate.right", 1)
                }
                .padding(.bottom, 32)
                Text("Щипком приблизьте, перетащите — что в рамке, то и останется.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.7)).padding(.bottom, 24)
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private func rotateButton(_ symbol: String, _ dir: Int) -> some View {
        Button {
            quarterTurns += dir
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: symbol).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 56, height: 56).background(.white.opacity(0.15), in: Circle())
        }
    }

    /// Картинка не должна уходить из рамки: после жеста подтягиваем к краям.
    private func clamp(frame: CGFloat) {
        let rotated = quarterTurns % 2 != 0
        let w = rotated ? image.size.height : image.size.width, h = rotated ? image.size.width : image.size.height
        let fit = min(frame / w, frame / h) * zoom
        let shownW = w * fit, shownH = h * fit
        let maxX = max(0, (shownW - frame) / 2), maxY = max(0, (shownH - frame) / 2)
        offset = CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
        offsetStart = offset
    }

    /// Рендер того, что видно в рамке, в квадрат ~1600 px теми же преобразованиями, что на экране.
    private func render(frame: CGFloat) -> UIImage {
        let out: CGFloat = 1600
        let k = out / frame
        let fit = min(frame / image.size.width, frame / image.size.height)
        let r = UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: .init())
        return r.image { ctx in
            let c = ctx.cgContext
            c.translateBy(x: out / 2 + offset.width * k, y: out / 2 + offset.height * k)
            c.rotate(by: CGFloat(quarterTurns) * .pi / 2)
            c.scaleBy(x: fit * zoom * k, y: fit * zoom * k)
            image.draw(in: CGRect(x: -image.size.width / 2, y: -image.size.height / 2, width: image.size.width, height: image.size.height))
        }
    }
}
