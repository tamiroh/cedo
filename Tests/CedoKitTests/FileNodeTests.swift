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

    @Test func readsThroughOnlyFoldersWithoutSubfolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        for path in [
            "連載/02-API の設計.md", "連載/01-環境構築.md", "連載/10-まとめ.md", "連載/.cache/x",
            "連載/node_modules/x", "書籍/第1章/01-導入.md", "書籍/はじめに.md",
        ] {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "".write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("下書き"), withIntermediateDirectories: true)

        #expect(
            FileNode(url: root.appendingPathComponent("連載")).readThroughFiles?.map(\.name) == [
                "01-環境構築.md", "02-API の設計.md", "10-まとめ.md",
            ])
        #expect(FileNode(url: root.appendingPathComponent("書籍")).readThroughFiles == nil)
        #expect(FileNode(url: root.appendingPathComponent("下書き")).readThroughFiles == nil)
    }
}
