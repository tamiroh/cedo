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
