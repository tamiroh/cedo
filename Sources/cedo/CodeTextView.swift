import AppKit
import SwiftUI

/// A monospaced plain-text editor with smart quotes and other automatic substitutions turned off.
struct CodeTextView: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.string = text
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        let textView = scrollView.documentView as! NSTextView
        // Replace the contents only when a different file has been loaded
        if textView.string != text {
            textView.string = text
            textView.undoManager?.removeAllActions()
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
    }
}
