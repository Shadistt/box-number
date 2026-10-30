import SwiftUI
import UIKit

/// Тап мимо поля ввода прячет клавиатуру — во всём приложении.
/// Распознаватель вешается на окно, не отменяет другие касания (кнопки, список), поэтому ничего не ломает.
struct KeyboardDismissOnTap: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let v = UIView(frame: .zero); v.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            guard let window = v.window, !(window.gestureRecognizers ?? []).contains(where: { $0.name == "boxno.dismissKeyboard" }) else { return }
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
            tap.name = "boxno.dismissKeyboard"
            tap.cancelsTouchesInView = false
            tap.delegate = context.coordinator
            window.addGestureRecognizer(tap)
        }
        return v
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @objc func tap() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
        /// Тап по самому полю ввода или клавиатуре — не наш случай.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var v = touch.view
            while let cur = v {
                if cur is UITextField || cur is UITextView || cur is UITextInput { return false }
                if String(describing: type(of: cur)).contains("Keyboard") { return false }
                v = cur.superview
            }
            return true
        }
    }
}
