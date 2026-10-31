import AppKit
import CedoKit
import SwiftUI

struct CodeTextView: NSViewRepresentable {
    let text: String
    let document: URL
    let lint: Workspace.Lint?
    let configuration: Configuration?
    let horizontalInset: CGFloat
    let onChange: (String) -> Void

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

    static let characterWidth = NSAttributedString(string: "あ", attributes: attributes).size().width

    func makeCoordinator() -> Coordinator { Coordinator(onChange: onChange) }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView(text: text, document: document)
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.update(
            text: text, document: document, lint: lint, configuration: configuration,
            horizontalInset: horizontalInset
        )
    }

    private static func setText(_ text: String, in textView: NSTextView) {
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate,
        NSViewToolTipOwner
    {
        var onChange: (String) -> Void
        var document: URL?
        weak var textView: NSTextView?
        private var shownLintID: UUID?
        private var toolTips: [NSView.ToolTipTag: String] = [:]
        private var needsToolTips = false
        private var appliedConfigurationID: UUID?
        private var highlightsAreStale = true

        private var layoutManager: LintLayoutManager? { textView?.layoutManager as? LintLayoutManager }

        init(onChange: @escaping (String) -> Void) { self.onChange = onChange }

        func makeScrollView(text: String, document: URL) -> NSScrollView {
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

            textView.delegate = self
            textStorage.delegate = self
            self.textView = textView
            textView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(frameDidChange),
                name: NSView.frameDidChangeNotification, object: textView
            )
            textView.isRichText = false
            textView.allowsUndo = true
            textView.backgroundColor = NSColor(Theme.background)
            textView.insertionPointColor = NSColor(Theme.text)
            textView.selectedTextAttributes = [.backgroundColor: NSColor(Theme.selection)]
            textView.typingAttributes = CodeTextView.attributes
            textView.textContainerInset = CodeTextView.textInset
            textView.textContainer?.lineFragmentPadding = 0
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            CodeTextView.setText(text, in: textView)
            self.document = document
            return scrollView
        }

        func update(
            text: String, document: URL, lint: Workspace.Lint?, configuration: Configuration?,
            horizontalInset: CGFloat
        ) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            if textView.textContainerInset.width != horizontalInset {
                textView.textContainerInset = NSSize(width: horizontalInset, height: CodeTextView.textInset.height)
                setNeedsToolTips()
            }
            let isNewDocument = self.document != document
            self.document = document
            if isNewDocument {
                CodeTextView.setText(text, in: textView)
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
                textView.scrollToBeginningOfDocument(nil)
                clearMarks()
            } else if textView.string != text, !textView.hasMarkedText() {
                // Only an outside change makes these differ, apart from text still being composed in an input method
                let selection = textView.selectedRange()
                let origin = scrollView.contentView.bounds.origin
                CodeTextView.setText(text, in: textView)
                textView.undoManager?.removeAllActions()
                let length = (text as NSString).length
                textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
                scrollView.contentView.scroll(to: origin)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
            show(lint, for: document)
            applyHighlights(of: configuration)
        }

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

        func textStorage(
            _ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange, changeInLength delta: Int
        ) {
            if editedMask.contains(.editedCharacters) {
                highlightsAreStale = true
            }
            guard editedMask.contains(.editedCharacters), let layoutManager, !layoutManager.marks.isEmpty else {
                return
            }
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

        func applyHighlights(of configuration: Configuration?) {
            guard highlightsAreStale || configuration?.id != appliedConfigurationID,
                let textView, let layoutManager
            else { return }
            highlightsAreStale = false
            appliedConfigurationID = configuration?.id
            let text = textView.string
            let all = NSRange(location: 0, length: (text as NSString).length)
            layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: all)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
            guard let configuration else { return }
            for match in configuration.highlightMatches(in: text) {
                let highlight = configuration.highlights[match.highlight]
                var attributes: [NSAttributedString.Key: Any] = [:]
                if let color = highlight.color {
                    attributes[.foregroundColor] = NSColor(Color(hex: color))
                }
                if let background = highlight.background {
                    attributes[.backgroundColor] = NSColor(Color(hex: background))
                }
                if attributes.isEmpty {
                    attributes[.backgroundColor] = NSColor(Theme.selection)
                }
                layoutManager.addTemporaryAttributes(attributes, forCharacterRange: match.range)
            }
        }

        @objc func frameDidChange() {
            setNeedsToolTips()
        }

        func setNeedsToolTips() {
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
                    forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: container
                ) { rect, _ in
                    let tag = textView.addToolTip(rect.offsetBy(dx: origin.x, dy: origin.y), owner: self, userData: nil)
                    self.toolTips[tag] = mark.message
                }
            }
        }

        func view(
            _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
            userData data: UnsafeMutableRawPointer?
        ) -> String {
            toolTips[tag] ?? ""
        }
    }
}
