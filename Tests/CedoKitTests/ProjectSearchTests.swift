import Foundation
import Testing

@testable import CedoKit

struct ProjectSearchTests {
    @Test func findsOccurrencesAtEditorOffsetsAcrossVisibleFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = nested.appendingPathComponent("draft.md")
        try "old".write(to: draft, atomically: true, encoding: .utf8)
        try Data([0xEF, 0xBB, 0xBF] + Array("Find".utf8)).write(to: root.appendingPathComponent("notes.md"))
        try Data([0, 70, 105, 110, 100]).write(to: root.appendingPathComponent("binary"))
        try "Find".write(to: root.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)
        let hits = try await ProjectSearch.find(
            "find", in: root, includesHiddenFiles: false, openFile: draft, openText: "📖\r\n前 FIND find")
        #expect(hits.map(\.line) == [2, 2, 1])
        #expect(hits.map(\.range.location) == [6, 11, 0])
        #expect(hits.map { ($0.source as NSString).substring(with: $0.range) } == ["FIND", "find", "Find"])
    }
}
