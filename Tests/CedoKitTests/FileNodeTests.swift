import Foundation
import Testing

@testable import CedoKit

struct FileNodeTests {
    @Test func showsHiddenFilesOnlyWhenAskedButNeverGit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        for name in ["a.md", ".cedo.json"] {
            try "".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        #expect(FileNode(url: root).children?.map(\.name) == ["a.md"])
        #expect(FileNode(url: root, includesHiddenFiles: true).children?.map(\.name) == [".cedo.json", "a.md"])
    }
}
