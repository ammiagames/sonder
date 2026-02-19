//
//  AutoFocusTextField.swift
//  sonder
//

import SwiftUI

/// UIKit-backed text field that auto-focuses the moment it enters the window
/// hierarchy, using `didMoveToWindow` — the earliest reliable point at which
/// `becomeFirstResponder()` will succeed, even inside a `fullScreenCover`.
struct AutoFocusTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var autoFocus: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> FocusableTextField {
        let tf = FocusableTextField()
        tf.placeholder = placeholder
        tf.font = UIFont.systemFont(ofSize: 17)
        tf.autocorrectionType = .no
        tf.returnKeyType = .search
        tf.delegate = context.coordinator
        tf.shouldAutoFocus = autoFocus
        tf.textColor = UIColor(SonderColors.inkDark)
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )
        // Proper sizing: hug vertically so it doesn't expand
        tf.setContentHuggingPriority(.required, for: .vertical)
        tf.setContentCompressionResistancePriority(.required, for: .vertical)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: FocusableTextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AutoFocusTextField
        init(_ parent: AutoFocusTextField) { self.parent = parent }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

/// Custom UITextField that calls `becomeFirstResponder()` in `didMoveToWindow`,
/// which is the earliest moment UIKit guarantees the responder chain is ready.
final class FocusableTextField: UITextField {
    var shouldAutoFocus = true

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if shouldAutoFocus, window != nil {
            shouldAutoFocus = false
            becomeFirstResponder()
        }
    }
}
