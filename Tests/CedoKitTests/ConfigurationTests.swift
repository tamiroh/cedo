import Foundation
import Testing

@testable import CedoKit

struct ConfigurationTests {
    @Test func readsColors() throws {
        let configuration = try configuration(
            ##"{ "highlights": [{ "pattern": "a", "color": "#8cb4f0", "background": "3A3220" }, { "pattern": "b" }] }"##
        )

        #expect(configuration.highlights[0].color == 0x8cb4f0)
        #expect(configuration.highlights[0].background == 0x3a3220)
        #expect(configuration.highlights[1].color == nil)
        #expect(configuration.highlights[1].background == nil)
    }

    @Test func highlightsMarkersInTechnicalWriting() throws {
        let configuration = try configuration(
            #"{ "highlights": [{ "pattern": "`[^`]+`" }, { "pattern": "\\b(TODO|FIXME)\\b" }, { "pattern": "https?://\\S+" }] }"#
        )
        let text = """
            `npm install` を実行する。TODO: 手順を確認
            詳しくは https://example.com/docs を参照。FIXME
            TODOS は対象外
            """

        #expect(
            matchedTexts(of: configuration, in: text) == [
                "`npm install`", "TODO", "FIXME", "https://example.com/docs",
            ])
    }

    @Test func anchorsMatchEachLine() throws {
        let configuration = try configuration(
            #"{ "highlights": [{ "pattern": "^#{1,6} .*$" }, { "pattern": "^> " }] }"#)
        let text = """
            # はじめに
            本文の # は見出しではない
            ## 準備
            > 引用
            これも > 引用ではない
            """

        #expect(matchedTexts(of: configuration, in: text) == ["# はじめに", "## 準備", "> "])
    }

    @Test func reportsOverlappingPatternsInTheirOrder() throws {
        let configuration = try configuration(#"{ "highlights": [{ "pattern": "TODO.*" }, { "pattern": "TODO" }] }"#)

        #expect(
            configuration.highlightMatches(in: "TODO 直す") == [
                .init(range: NSRange(location: 0, length: 7), highlight: 0),
                .init(range: NSRange(location: 0, length: 4), highlight: 1),
            ])
    }

    @Test func countsRangesInUTF16() throws {
        let configuration = try configuration(#"{ "highlights": [{ "pattern": "`[^`]+`" }] }"#)

        // 𠮷 and 👍 take two UTF-16 code units each
        #expect(
            configuration.highlightMatches(in: "𠮷は👍`ls`") == [
                .init(range: NSRange(location: 5, length: 4), highlight: 0)
            ])
    }

    @Test func skipsEmptyMatches() throws {
        let configuration = try configuration(#"{ "highlights": [{ "pattern": "x*" }] }"#)

        #expect(matchedTexts(of: configuration, in: "axxbx") == ["xx", "x"])
    }

    @Test func readsTheFileInAFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cedo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(try Configuration(root: root) == nil)

        try Data(#"{ "highlights": [{ "pattern": "TODO" }] }"#.utf8).write(to: Configuration.url(in: root))
        #expect(try Configuration(root: root)?.highlights.count == 1)

        try Data("{".utf8).write(to: Configuration.url(in: root))
        #expect(throws: Configuration.Failure.self) { try Configuration(root: root) }
    }

    @Test func rejectsBrokenSettings() {
        for settings in [
            "{",
            #"{ "highlights": {} }"#,
            ##"{ "highlights": [{ "color": "#ffffff" }] }"##,
            #"{ "highlights": [{ "pattern": "(" }] }"#,
            #"{ "highlights": [{ "pattern": "a", "color": "red" }] }"#,
            ##"{ "highlights": [{ "pattern": "a", "background": "#fff" }] }"##,
        ] {
            #expect(throws: Configuration.Failure.self, "\(settings)") { try configuration(settings) }
        }
    }

    @Test func allowsSettingsWithoutHighlights() throws {
        #expect(try configuration("{}").highlights.isEmpty)
        #expect(try configuration(#"{ "highlights": [] }"#).highlights.isEmpty)
        #expect(try configuration(#"{ "theme": "dark" }"#).highlights.isEmpty)
    }

    private func configuration(_ settings: String) throws -> Configuration {
        try Configuration(data: Data(settings.utf8))
    }

    private func matchedTexts(of configuration: Configuration, in text: String) -> [String] {
        configuration.highlightMatches(in: text).map { (text as NSString).substring(with: $0.range) }
    }
}
