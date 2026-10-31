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

    final class Coordinator: NSObject {
        var parent: ListLongPress
        private weak var recognizer: UILongPressGestureRecognizer?
        init(_ parent: ListLongPress) { self.parent = parent }
        deinit { if let r = recognizer { r.view?.removeGestureRecognizer(r) } }

        func attach(to scroll: UIScrollView) {
            guard recognizer == nil else { return }
            let g = UILongPressGestureRecognizer(target: self, action: #selector(handle))
            g.minimumPressDuration = 0.35
            g.allowableMovement = 8
            scroll.addGestureRecognizer(g)
            recognizer = g
        }

        @objc private func handle(_ g: UILongPressGestureRecognizer) {
            let p = g.location(in: nil)
            switch g.state {
            case .began: parent.began(p)
            case .changed: parent.moved(p)
            case .ended: parent.ended(p)
            default: parent.cancelled()
            }
        }
    }
}
