import SwiftUI
import UIKit

/// «Зажать и тянуть» в списке через UIKit-распознаватель на самом UIScrollView.
/// SwiftUI-жесты внутри ScrollView либо глотали прокрутку, либо тапы, либо срабатывал тап при отпускании (релизы 41–43).
/// UILongPressGestureRecognizer: пока палец не держат 0,35 с — прокрутка и кнопки работают как обычно;
/// сработал — отменяет касания у SwiftUI (cancelsTouchesInView), поэтому кнопка карточки не нажмётся при отпускании.
/// Точки — в координатах окна, совпадают с `.global` в SwiftUI.
struct ListLongPress: UIViewRepresentable {
    var began: (CGPoint) -> Void
    var moved: (CGPoint) -> Void
    var ended: (CGPoint) -> Void
    var cancelled: () -> Void

    func makeUIView(context: Context) -> AttachView {
        let v = AttachView(frame: .zero)
        v.isUserInteractionEnabled = false           // сам вид касания не ловит — только находит UIScrollView
        v.onAttach = { [weak coordinator = context.coordinator] scroll in coordinator?.attach(to: scroll) }
        return v
    }
    func updateUIView(_ uiView: AttachView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class AttachView: UIView {
        var onAttach: ((UIScrollView) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var s = superview
            while let cur = s, !(cur is UIScrollView) { s = cur.superview }
            if let scroll = s as? UIScrollView { onAttach?(scroll) }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ListLongPress
        private weak var recognizer: UILongPressGestureRecognizer?
        init(_ parent: ListLongPress) { self.parent = parent }
        deinit { if let r = recognizer { r.view?.removeGestureRecognizer(r) } }

        func attach(to scroll: UIScrollView) {
            guard recognizer == nil else { return }
            let g = UILongPressGestureRecognizer(target: self, action: #selector(handle))
            g.minimumPressDuration = 0.35
            g.allowableMovement = 8
            g.delegate = self
            scroll.addGestureRecognizer(g)
            recognizer = g
        }

        /// SwiftUI держит на корневом виде свои распознаватели (кнопка, прокрутка) и по умолчанию они «побеждают» наш:
        /// в сборке 78 долгое нажатие не срабатывало вовсе. Разрешаем одновременное распознавание.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // Автопрокрутка у краёв: палец с карточкой у верха/низа списка — список едет сам (как в UIKit-списках).
        private var displayLink: CADisplayLink?
        private var lastPoint: CGPoint = .zero
        private var offsetAtBegan: CGFloat = 0
        private var scrollSpeed: CGFloat = 0        // pt за кадр, знак — направление
        private let edge: CGFloat = 72
        private let maxSpeed: CGFloat = 14

        /// Точка для SwiftUI: окно + сколько список уехал с момента подъёма — карточка остаётся «под пальцем» относительно содержимого.
        private func adjusted(_ scroll: UIScrollView?) -> CGPoint {
            CGPoint(x: lastPoint.x, y: lastPoint.y + ((scroll?.contentOffset.y ?? offsetAtBegan) - offsetAtBegan))
        }

        @objc private func handle(_ g: UILongPressGestureRecognizer) {
            let scroll = g.view as? UIScrollView
            lastPoint = g.location(in: nil)
            switch g.state {
            case .began:
                // Карточка поднялась — прокрутку этого касания обрываем сразу (scrollDisabled в SwiftUI догонит на следующем кадре).
                scroll?.panGestureRecognizer.isEnabled = false; scroll?.panGestureRecognizer.isEnabled = true
                offsetAtBegan = scroll?.contentOffset.y ?? 0
                parent.began(lastPoint)
                startAutoScroll(scroll)
            case .changed:
                updateSpeed(scroll)
                parent.moved(adjusted(scroll))
            case .ended:
                stopAutoScroll()
                parent.ended(adjusted(scroll))
            default:
                stopAutoScroll()
                parent.cancelled()
            }
        }

        private func updateSpeed(_ scroll: UIScrollView?) {
            guard let scroll else { scrollSpeed = 0; return }
            let y = scroll.convert(lastPoint, from: nil).y - scroll.contentOffset.y     // в видимой области
            let top = scroll.adjustedContentInset.top, bottom = scroll.bounds.height - scroll.adjustedContentInset.bottom
            if y < top + edge { scrollSpeed = -maxSpeed * min(1, (top + edge - y) / edge) }
            else if y > bottom - edge { scrollSpeed = maxSpeed * min(1, (y - (bottom - edge)) / edge) }
            else { scrollSpeed = 0 }
        }

        private func startAutoScroll(_ scroll: UIScrollView?) {
            guard scroll != nil, displayLink == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        private func stopAutoScroll() { displayLink?.invalidate(); displayLink = nil; scrollSpeed = 0 }

        @objc private func tick() {
            guard scrollSpeed != 0, let scroll = recognizer?.view as? UIScrollView else { return }
            let minY = -scroll.adjustedContentInset.top
            let maxY = max(minY, scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
            let y = min(max(scroll.contentOffset.y + scrollSpeed, minY), maxY)
            guard y != scroll.contentOffset.y else { return }
            scroll.contentOffset.y = y
            parent.moved(adjusted(scroll))
        }
    }
}
