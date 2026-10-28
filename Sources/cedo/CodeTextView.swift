import AppKit
import SwiftUI

/// A monospaced plain-text editor with smart quotes and other automatic substitutions turned off.
struct CodeTextView: NSViewRepresentable {
    let text: String
    let onChange: (String) -> Void

    private static let attributes: [NSAttributedString.Key: Any] = {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 5
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(Theme.text),
            .paragraphStyle: paragraph,
        ]
    }()

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.backgroundColor = NSColor(Theme.inset)
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = NSColor(Theme.inset)
        textView.insertionPointColor = NSColor(Theme.text)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(Theme.selection)]
        textView.typingAttributes = Self.attributes
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        setText(text, in: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        let textView = scrollView.documentView as! NSTextView
        // Replace the contents only when a different file has been loaded
        if textView.string != text {
            setText(text, in: textView)
            textView.undoManager?.removeAllActions()
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    private func setText(_ text: String, in textView: NSTextView) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
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
