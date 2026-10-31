import CedoKit
import Foundation
import Testing

struct DocumentTests {
    let file: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("chapter.md")
        try write("original")
    }

    @Test func refusesTextThatIsNotUTF8() throws {
        try Data([0x82, 0xa0]).write(to: file)
        #expect(Document(url: file) == nil)
    }

    @Test func savesEdits() throws {
        var document = try #require(Document(url: file))
        document.text = "edited"

        #expect(try document.save() == .saved)
        #expect(try onDisk() == "edited")
        #expect(!document.isDirty)
        #expect(try document.save() == .unchanged)
    }

    @Test func leavesAFileChangedOutsideAloneOnSave() throws {
        var document = try #require(Document(url: file))
        document.text = "mine"
        try write("theirs")

        #expect(try document.save() == .conflict(onDisk: "theirs"))
        #expect(try onDisk() == "theirs")

        #expect(try document.save(overwritingOutsideChanges: true) == .saved)
        #expect(try onDisk() == "mine")
    }

    @Test func reloadsOutsideChangesWithoutEdits() throws {
        var document = try #require(Document(url: file))
        #expect(document.checkForOutsideChanges() == .unchanged)

        try write("theirs")
        #expect(document.checkForOutsideChanges() == .reloaded)
        #expect(document.text == "theirs")
        #expect(!document.isDirty)
        #expect(document.checkForOutsideChanges() == .unchanged)
    }

    @Test func reportsOutsideChangesThatClashWithEdits() throws {
        var document = try #require(Document(url: file))
        document.text = "mine"
        try write("theirs")

        #expect(document.checkForOutsideChanges() == .conflict(onDisk: "theirs"))
        #expect(document.text == "mine")

        document.adopt("theirs")
        #expect(document.text == "theirs")
        #expect(!document.isDirty)
    }

    @Test func stopsSavingWhenTheFileCannotBeRead() throws {
        var document = try #require(Document(url: file))
        document.text = "mine"

        let utf16 = try #require("theirs".data(using: .utf16))
        try utf16.write(to: file)
        #expect(try document.save() == .unreadable)
        #expect(try Data(contentsOf: file) == utf16)

        try FileManager.default.removeItem(at: file)
        #expect(try document.save() == .unreadable)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func ignoresATouchThatKeepsTheContent() throws {
        var document = try #require(Document(url: file))
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: file.path)

        #expect(document.checkForOutsideChanges() == .unchanged)
        #expect(!document.isDirty)
    }

    private func write(_ text: String) throws {
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    private func onDisk() throws -> String {
        try String(contentsOf: file, encoding: .utf8)
    }
}
