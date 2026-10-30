import Foundation
import Testing

@testable import CedoKit

struct ConfigurationTests {
    @Test func matchesEachRule() throws {
        let settings = """
            { "highlights": [
              { "pattern": "「[^」]*」", "color": "#8cb4f0" },
              { "pattern": "^TODO", "background": "3a3220" }
            ] }
            """
        let configuration = try Configuration(data: Data(settings.utf8))

        #expect(configuration.highlights[0].color == 0x8cb4f0)
        #expect(configuration.highlights[1].background == 0x3a3220)
        // 𠮷 takes two UTF-16 code units
        #expect(
            configuration.highlightMatches(in: "𠮷は「やあ」と言った。\nTODO 直す") == [
                .init(range: NSRange(location: 3, length: 4), highlight: 0),
                .init(range: NSRange(location: 13, length: 4), highlight: 1),
            ])
    }

    @Test func rejectsBrokenSettings() {
        #expect(throws: Configuration.Failure.self) { try Configuration(data: Data("{".utf8)) }
        #expect(throws: Configuration.Failure.self) {
            try Configuration(data: Data(#"{ "highlights": [{ "pattern": "(" }] }"#.utf8))
        }
        #expect(throws: Configuration.Failure.self) {
            try Configuration(data: Data(#"{ "highlights": [{ "pattern": "a", "color": "red" }] }"#.utf8))
        }
    }

    @Test func allowsSettingsWithoutHighlights() throws {
        #expect(try Configuration(data: Data("{}".utf8)).highlights.isEmpty)
    }
}
