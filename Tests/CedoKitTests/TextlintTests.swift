import Foundation
import Testing

@testable import CedoKit

struct TextlintTests {
    @Test func parsesMessages() throws {
        let output = """
            [{"messages":[
              {"ruleId":"japanese/max-ten","message":"Too many commas","index":13,"range":[13,14],"severity":2},
              {"ruleId":"old-rule","message":"No range\\n","index":20,"severity":1},
              {"ruleId":"empty","message":"Empty range","index":30,"range":[30,30],"severity":2}
            ],"filePath":"a.md"}]
            """
        let diagnostics = try Textlint.parse(Data(output.utf8))

        #expect(
            diagnostics == [
                .init(
                    range: NSRange(location: 13, length: 1), message: "Too many commas", ruleID: "japanese/max-ten",
                    isError: true),
                .init(range: NSRange(location: 20, length: 1), message: "No range", ruleID: "old-rule", isError: false),
                .init(range: NSRange(location: 30, length: 1), message: "Empty range", ruleID: "empty", isError: true),
            ])
    }

    @Test func needsBothConfigurationAndInstallation() throws {
        let root = try makeProject(config: false, script: nil)
        #expect(Textlint(root: root) == nil)

        try "{}".write(to: root.appendingPathComponent(".textlintrc.json"), atomically: true, encoding: .utf8)
        #expect(Textlint(root: root) == nil)

        try installScript("#!/bin/sh\n", in: root)
        #expect(Textlint(root: root) != nil)
    }

    @Test func cancelsBeforeTheProcessStarts() async throws {
        let root = try makeProject(config: true, script: "#!/bin/sh\nsleep 1\necho '[]'\n")
        let textlint = try #require(Textlint(root: root))
        let task = Task { try await textlint.lint("text", of: root.appendingPathComponent("a.md")) }
        task.cancel()

        await #expect(throws: CancellationError.self) { try await task.value }
    }

    private func makeProject(config: Bool, script: String?) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("node_modules/.bin"), withIntermediateDirectories: true)
        if config {
            try "{}".write(to: root.appendingPathComponent(".textlintrc.json"), atomically: true, encoding: .utf8)
        }
        if let script {
            try installScript(script, in: root)
        }
        return root
    }

    private func installScript(_ script: String, in root: URL) throws {
        let executable = root.appendingPathComponent("node_modules/.bin/textlint")
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }
}
