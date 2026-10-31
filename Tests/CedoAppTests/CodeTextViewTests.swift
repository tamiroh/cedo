import AppKit
import Testing

@testable import CedoApp
@testable import CedoKit

@MainActor
struct CodeTextViewTests {
    @Test func reportsTyping() {
        let editor = Editor("API の説明")

        editor.type("新しい ", at: 0)

        #expect(editor.changes == ["新しい API の説明"])
    }

    @Test func marksTheLintedText() {
        let editor = Editor("この API は非推奨です。")

        editor.update(
            lint: editor.lint(errorAt: NSRange(location: 3, length: 3), warningAt: NSRange(location: 7, length: 3)))

        #expect(editor.marks == [NSRange(location: 3, length: 3), NSRange(location: 7, length: 3)])
        #expect(editor.layoutManager.marks.map(\.isError) == [true, false])
        #expect(editor.layoutManager.marks[0].message == "message\n\nrule")
    }

    @Test func ignoresLintForOtherTextOrFiles() {
        let editor = Editor("この API は非推奨です。")
        let range = NSRange(location: 3, length: 3)

        editor.update(lint: Workspace.Lint(file: editor.document, text: "古い本文", diagnostics: [diagnostic(range)]))
        editor.update(
            lint: Workspace.Lint(
                file: URL(fileURLWithPath: "/docs/other.md"), text: editor.textView.string,
                diagnostics: [diagnostic(range)]))

        #expect(editor.marks.isEmpty)
    }

    @Test func movesMarksWithEditsAndDropsEditedOnes() {
        let editor = Editor("aaa bbb ccc")
        editor.update(
            lint: Workspace.Lint(
                file: editor.document, text: "aaa bbb ccc",
                diagnostics: [0, 4, 8].map { diagnostic(NSRange(location: $0, length: 3)) }))

        editor.type("XX", at: 5)

        #expect(editor.marks == [NSRange(location: 0, length: 3), NSRange(location: 10, length: 3)])
    }

    @Test func takesInOutsideChangesKeepingTheCaret() {
        let editor = Editor("hello world")
        editor.type("!", at: 11)
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))

        editor.update("hello there world")

        #expect(editor.textView.string == "hello there world")
        #expect(editor.textView.selectedRange() == NSRange(location: 5, length: 0))
        #expect(editor.textView.undoManager?.canUndo == false)

        editor.textView.setSelectedRange(NSRange(location: 17, length: 0))
        editor.update("hi")

        #expect(editor.textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test func keepsTextBeingComposed() {
        let editor = Editor("API の")
        editor.textView.setSelectedRange(NSRange(location: 5, length: 0))
        editor.textView.setMarkedText(
            "せつめい", selectedRange: NSRange(location: 4, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))

        editor.update("API の")

        #expect(editor.textView.hasMarkedText())
        #expect(editor.textView.string == "API のせつめい")
    }

    @Test func startsOverForAnotherDocument() {
        let editor = Editor("aaa bbb")
        editor.update(lint: editor.lint(errorAt: NSRange(location: 0, length: 3)))
        editor.type("x", at: 7)

        editor.update("別の文書", document: URL(fileURLWithPath: "/docs/other.md"))

        #expect(editor.textView.string == "別の文書")
        #expect(editor.marks.isEmpty)
        #expect(editor.textView.selectedRange() == NSRange(location: 0, length: 0))
        #expect(editor.textView.undoManager?.canUndo == false)
    }

    @Test func highlightsMatchesAndFollowsEdits() throws {
        let editor = Editor("手順 TODO")
        let configuration = try Configuration(
            data: Data(##"{ "highlights": [{ "pattern": "TODO", "background": "#3a3220" }] }"##.utf8))

        editor.update(configuration: configuration)

        #expect(editor.highlighted == [3..<7])

        editor.type("TODO ", at: 0)
        editor.update(configuration: configuration)

        #expect(editor.highlighted == [0..<4, 8..<12])

        editor.update(configuration: nil)

        #expect(editor.highlighted.isEmpty)
    }
}

private func diagnostic(_ range: NSRange, isError: Bool = true) -> Textlint.Diagnostic {
    Textlint.Diagnostic(range: range, message: "message", ruleID: "rule", isError: isError)
}

@MainActor
private final class Editor {
    let document = URL(fileURLWithPath: "/docs/draft.md")
    let coordinator = CodeTextView.Coordinator(onChange: { _ in })
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered,
        defer: true)
    private(set) var changes: [String] = []
    private var lint: Workspace.Lint?
    private var configuration: Configuration?

    init(_ text: String) {
        window.isReleasedWhenClosed = false
        // The window gives the text view its undo manager
        window.contentView = coordinator.makeScrollView(text: text, document: document)
        coordinator.onChange = { [unowned self] in changes.append($0) }
    }

    var textView: NSTextView { coordinator.textView! }
    var layoutManager: LintLayoutManager { textView.layoutManager as! LintLayoutManager }
    var marks: [NSRange] { layoutManager.marks.map(\.range) }

    var highlighted: [Range<Int>] {
        var ranges: [Range<Int>] = []
        var index = 0
        let length = (textView.string as NSString).length
        while index < length {
            var effective = NSRange()
            let value = layoutManager.temporaryAttribute(
                .backgroundColor, atCharacterIndex: index, effectiveRange: &effective)
            if value != nil {
                ranges.append(effective.location..<NSMaxRange(effective))
            }
            index = NSMaxRange(effective)
        }
        return ranges
    }

    func lint(errorAt error: NSRange, warningAt warning: NSRange? = nil) -> Workspace.Lint {
        Workspace.Lint(
            file: document, text: textView.string,
            diagnostics: [diagnostic(error)] + (warning.map { [diagnostic($0, isError: false)] } ?? []))
    }

    func type(_ text: String, at location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    /// Updates as SwiftUI would, with the latest text unless another is given.
    func update(_ text: String? = nil, document: URL? = nil) {
        coordinator.update(
            text: text ?? textView.string, document: document ?? self.document, lint: lint,
            configuration: configuration, horizontalInset: CodeTextView.textInset.width)
    }

    func update(lint: Workspace.Lint?) {
        self.lint = lint
        update()
    }

    func update(configuration: Configuration?) {
        self.configuration = configuration
        update()
    }
}
