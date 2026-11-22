import Foundation
import Testing

@testable import CedoHistory

struct GitTests {
    @Test func previewsEditorTextBeforeAndAfterRecordingAnEdit() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Git.createRepository(in: directory)
        let file = directory.appendingPathComponent("Draft.md")
        try Data("First draft".utf8).write(to: file)
        #expect(try await Git.history(of: file).isEmpty)
        #expect(try await Git.currentDiff(of: file, text: "First draft").contains("+First draft"))
        try Git.runSync(["add", "."], in: directory)
        try Git.runSync(
            ["-c", "user.name=Writer", "-c", "user.email=writer@example.org", "commit", "-qm", "Edit"],
            in: directory)
        #expect(try await Git.currentDiff(of: file, text: "First draft").isEmpty)
        let patch = try await Git.currentDiff(of: file, text: "Revised draft")
        #expect(patch.contains("-First draft"))
        #expect(patch.contains("+Revised draft"))
        #expect(try String(contentsOf: file, encoding: .utf8) == "First draft")
    }

    @Test func measuresEachChangeInCharacters() async throws {
        let repository = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let file = repository.appendingPathComponent("記事.md")
        try Git.runSync(["init", "--quiet"], in: repository)
        try Git.runSync(["config", "user.name", "cedo tests"], in: repository)
        try Git.runSync(["config", "user.email", "tests@example.com"], in: repository)
        func commit(_ text: String) throws {
            try text.write(to: file, atomically: true, encoding: .utf8)
            try Git.runSync(["add", "."], in: repository)
            try Git.runSync(["commit", "--quiet", "-m", "Edit"], in: repository)
        }

        try commit("# 導入\n\nnpm でインストールする。\n")
        try commit("# 導入\n\npnpm でインストールする。\n\n## 設定\n")
        try commit("# 導入\n\npnpm でインストールする。\n")

        let history = try await Git.history(of: file)
        #expect(history.map(\.path) == ["記事.md", "記事.md", "記事.md"])
        #expect(history.map(\.added) == [0, 6, 18])
        #expect(history.map(\.removed) == [5, 0, 0])
    }
}
