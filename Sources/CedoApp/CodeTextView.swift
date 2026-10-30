import AppKit
import SwiftUI

/// A monospaced plain-text editor with smart quotes and other automatic substitutions turned off.
struct CodeTextView: NSViewRepresentable {
    let text: String
    /// The file being edited. A new document resets the scroll position and undo history.
    let document: URL
    let lint: Workspace.Lint?
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
        // Built by hand on TextKit 1, because the lint marks are drawn by the layout manager
        let textStorage = NSTextStorage()
        let layoutManager = LintLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.backgroundColor = NSColor(Theme.background)

        textView.delegate = context.coordinator
        textStorage.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.frameDidChange),
            name: NSView.frameDidChangeNotification, object: textView
        )
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
            context.coordinator.clearMarks()
        } else if textView.string != text {
            // Typing keeps the two in sync, so a difference means the file was reloaded after an outside change
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
        context.coordinator.show(lint, for: document)
    }

    private func setText(_ text: String, in textView: NSTextView) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: Self.attributes))
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSViewToolTipOwner {
        var onChange: (String) -> Void
        var document: URL?
        weak var textView: NSTextView?
        private var shownLintID: UUID?
        private var toolTips: [NSView.ToolTipTag: String] = [:]
        private var needsToolTips = false

        private var layoutManager: LintLayoutManager? { textView?.layoutManager as? LintLayoutManager }

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onChange(textView.string)
        }

        func show(_ lint: Workspace.Lint?, for document: URL) {
            guard lint?.id != shownLintID, let textView, let layoutManager else { return }
            guard let lint else {
                clearMarks()
                return
            }
            // A report on older text is dropped; the one for the current text is on its way
            guard lint.file == document, lint.text == textView.string else { return }
            shownLintID = lint.id
            let length = (textView.string as NSString).length
            layoutManager.marks = lint.diagnostics.compactMap { diagnostic in
                guard NSMaxRange(diagnostic.range) <= length else { return nil }
                return LintLayoutManager.Mark(
                    range: diagnostic.range,
                    message: "\(diagnostic.message)\n\n\(diagnostic.ruleID)",
                    isError: diagnostic.isError
                )
            }
            textView.needsDisplay = true
            setNeedsToolTips()
        }

        func clearMarks() {
            shownLintID = nil
            layoutManager?.marks = []
            textView?.needsDisplay = true
            setNeedsToolTips()
        }

        /// Moves the marks along with edits made before them, and drops the ones whose text was edited.
        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), let layoutManager, !layoutManager.marks.isEmpty else { return }
            let oldEnd = NSMaxRange(editedRange) - delta
            layoutManager.marks = layoutManager.marks.compactMap { mark in
                if NSMaxRange(mark.range) <= editedRange.location {
                    return mark
                }
                guard mark.range.location >= oldEnd else { return nil }
                var moved = mark
                moved.range.location += delta
                return moved
            }
            setNeedsToolTips()
        }

        @objc func frameDidChange() {
            setNeedsToolTips()
        }

        /// Rebuilds the hover areas once the current change has been laid out.
        private func setNeedsToolTips() {
            guard !needsToolTips else { return }
            needsToolTips = true
            DispatchQueue.main.async { [weak self] in
                self?.needsToolTips = false
                self?.updateToolTips()
            }
        }

        private func updateToolTips() {
            guard let textView, let layoutManager, let container = textView.textContainer else { return }
            textView.removeAllToolTips()
            toolTips = [:]
            let origin = textView.textContainerOrigin
            for mark in layoutManager.marks {
                let glyphs = layoutManager.glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container
                ) { rect, _ in
                    let tag = textView.addToolTip(rect.offsetBy(dx: origin.x, dy: origin.y), owner: self, userData: nil)
                    self.toolTips[tag] = mark.message
                }
            }
        }

        func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
            toolTips[tag] ?? ""
        }
    }
}
