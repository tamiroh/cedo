import Foundation
import Testing

@testable import CedoKit

struct GitTests {
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
