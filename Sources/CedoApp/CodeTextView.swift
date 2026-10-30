import AppKit
import SwiftUI

/// A monospaced plain-text editor with smart quotes and other automatic substitutions turned off.
struct CodeTextView: NSViewRepresentable {
    let text: String
    /// The file being edited. A new document resets the scroll position and undo history.
    let document: URL
    let onChange: (String) -> Void

    /// Views above the text use the same horizontal inset to line up with it.
    static let textInset = NSSize(width: 32, height: 12)

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
        scrollView.backgroundColor = NSColor(Theme.background)
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = NSColor(Theme.background)
        textView.insertionPointColor = NSColor(Theme.text)
        textView.selectedTextAttributes = [.backgroundColor: NSColor(Theme.selection)]
        textView.typingAttributes = Self.attributes
        textView.textContainerInset = Self.textInset
        textView.textContainer?.lineFragmentPadding = 0
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        setText(text, in: textView)
        context.coordinator.document = document
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        let textView = scrollView.documentView as! NSTextView
        let isNewDocument = context.coordinator.document != document
        context.coordinator.document = document
        if isNewDocument {
            setText(text, in: textView)
            textView.undoManager?.removeAllActions()
            textView.scrollToBeginningOfDocument(nil)
            return
        }
        // Typing keeps the two in sync, so a difference means the file was reloaded after an outside change
        guard textView.string != text else { return }
        let selection = textView.selectedRange()
        let origin = scrollView.contentView.bounds.origin
        setText(text, in: textView)
        textView.undoManager?.removeAllActions()
        // Keep the caret and scroll position where they were
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func setText(_ text: String, in textView: NSTextView) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: (String) -> Void
        var document: URL?

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }
    }
}
