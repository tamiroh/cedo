import Foundation
import Testing

@testable import CedoKit

@MainActor
struct AutoCommitterTests {
    let repository: URL

    init() throws {
        repository = FileManager.default.temporaryDirectory
            .appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try git("init", "--quiet")
        try git("config", "user.name", "cedo tests")
        try git("config", "user.email", "tests@example.com")
        try write("first", to: "edited.md")
        try write("same", to: "unchanged.md")
        try git("add", ".")
        try git("commit", "--quiet", "-m", "Initial")
    }

    @Test func commitsOnlySavedFilesThatChanged() throws {
        try write("first and more", to: "edited.md")
        try write("brand new", to: "new.md")
        try write("someone else's", to: "staged.md")
        try git("add", "staged.md")

        let committer = AutoCommitter(log: DebugLog())
        for name in ["edited.md", "new.md", "unchanged.md"] {
            committer.fileSaved(file(name))
        }
        committer.flushAndWait()

        let committed = try git("show", "--name-only", "--format=", "HEAD")
        #expect(committed.split(separator: "\n") == ["edited.md", "new.md"])
        #expect(try git("log", "-1", "--format=%B").contains("- edited.md (+9 chars)"))
        // The file staged outside cedo stays staged and uncommitted
        #expect(try git("diff", "--cached", "--name-only") == "staged.md\n")
    }

    @Test func readsFileNamesLiterally() throws {
        try write("a", to: "a*.md")
        try write("b", to: "another.md")

        let committer = AutoCommitter(log: DebugLog())
        committer.fileSaved(file("a*.md"))
        committer.flushAndWait()

        #expect(try git("show", "--name-only", "--format=", "HEAD") == "a*.md\n")
        #expect(try git("status", "--porcelain", "--", "another.md") == "?? another.md\n")
    }

    @Test func leavesAFileWithStagedChangesAlone() throws {
        try write("staged only", to: "edited.md")
        try git("add", "edited.md")
        try write("in the working tree", to: "edited.md")

        let committer = AutoCommitter(log: DebugLog())
        committer.fileSaved(file("edited.md"))
        committer.flushAndWait()

        #expect(try git("rev-list", "--count", "HEAD") == "1\n")
        #expect(try git("show", ":edited.md") == "staged only")
    }

    @Test func makesNoCommitWhenNothingChanged() throws {
        let committer = AutoCommitter(log: DebugLog())
        committer.fileSaved(file("unchanged.md"))
        committer.flushAndWait()

        #expect(try git("rev-list", "--count", "HEAD") == "1\n")
    }

    @Test func describesASingleFile() {
        let change = AutoCommitter.Change(file: file("01.md"), characterDelta: -3)
        #expect(AutoCommitter.message(for: [change]) == "Edit 01.md (-3 chars)")
    }

    private func file(_ name: String) -> URL {
        repository.appendingPathComponent(name)
    }

    private func write(_ text: String, to name: String) throws {
        try text.write(to: file(name), atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func git(_ arguments: String...) throws -> String {
        try Git.runSync(arguments, in: repository)
    }
}
