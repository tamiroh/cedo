import Foundation
import Testing

@testable import CedoKit

struct CharacterCountTests {
    @Test func leavesOutSpacesAndLineBreaks() {
        #expect(CharacterCount.of("# 導入\n\nnpm で\tインストールする。\r\n　全角スペース") == 22)
    }

    @Test func countsWhatReadsAsOneCharacter() {
        #expect(CharacterCount.of("か\u{3099}👨‍👩‍👧🇯🇵") == 3)
    }

    @Test func readsOnlyUTF8Text() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = folder.appendingPathComponent("記事.md")
        try Data([0xEF, 0xBB, 0xBF] + Array("本文 です".utf8)).write(to: text)
        let image = folder.appendingPathComponent("図.png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]).write(to: image)
        let latin1 = folder.appendingPathComponent("old.txt")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: latin1)

        #expect(CharacterCount.of(file: text) == 4)
        #expect(CharacterCount.of(file: image) == nil)
        #expect(CharacterCount.of(file: latin1) == nil)
    }
}

struct FolderCharacterCountTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("cedo-tests-\(UUID().uuidString)")

    init() throws {
        for (path, text) in [
            "はじめに.md": "本文です。",
            "章/1.md": "一章",
            "章/2.md": "二章 の 本文",
            ".notes.md": "隠し",
            "node_modules/pkg/README.md": "dependency",
            "package.json": #"{ "private": true }"#,
            "章/.build/out.txt": "generated",
        ] {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    @Test func addsUpFilesInSubfoldersButNotToolFolders() {
        #expect(CharacterCount.of(folder: root, includesHiddenFiles: false) == 5 + 2 + 5)
        #expect(CharacterCount.of(folder: root.appendingPathComponent("章"), includesHiddenFiles: false) == 7)
        #expect(
            CharacterCount.of(folder: root.appendingPathComponent("node_modules"), includesHiddenFiles: false) == nil)
    }

    @Test func countsHiddenFilesOnlyWhenShown() {
        #expect(CharacterCount.of(folder: root, includesHiddenFiles: true) == 5 + 2 + 5 + 2)
    }

    @Test func leavesOutTheExcludedFile() {
        let excluded = root.appendingPathComponent("章/2.md")

        #expect(CharacterCount.of(folder: root, includesHiddenFiles: false, excluding: excluded) == 5 + 2)
    }

    @Test func countsAgainAfterTheFileChanges() throws {
        let file = root.appendingPathComponent("章/1.md")
        #expect(CharacterCount.of(file: file) == 2)

        try "一章を書き足した".write(to: file, atomically: true, encoding: .utf8)

        #expect(CharacterCount.of(file: file) == 8)
    }
}
