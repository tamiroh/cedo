import Foundation

public enum MarkdownSyntax {
    public enum Style: Equatable, Sendable {
        case heading, quote, marker, emphasis, link, url, code
    }

    public struct Span: Equatable, Sendable {
        /// In UTF-16 code units, as in `NSString`.
        public let range: NSRange
        public let style: Style
    }

    private struct Rule: @unchecked Sendable {
        let regex: NSRegularExpression
        let style: Style
        let group: Int

        init(_ pattern: String, _ style: Style, group: Int = 0) {
            // The patterns are fixed, so a failure is a bug caught by the tests
            regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
            self.style = style
            self.group = group
        }
    }

    private static let fileExtensions: Set<String> = ["md", "markdown"]

    private static let rules = [
        Rule(#"^ {0,3}#{1,6}(?:[ \t].*)?$"#, .heading),
        Rule(#"^ {0,3}>.*$"#, .quote),
        Rule(#"^[ \t]*([-*+]|\d{1,9}[.)])[ \t](?![-*_ \t]*$)"#, .marker, group: 1),
        Rule(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#, .marker),
        Rule(#"\*\*[^*\n]+\*\*|__[^_\n]+__"#, .emphasis),
        Rule(#"(?<![*\w])\*[^*\s](?:[^*\n]*[^*\s])?\*(?!\*)|(?<![_\w])_[^_\s](?:[^_\n]*[^_\s])?_(?![_\w])"#, .emphasis),
        Rule(#"!?\[[^\]\n]*\](?=\()"#, .link),
        Rule(#"(?<=\])\([^)\s]+(?:[ \t]+"[^"\n]*")?\)|<https?://[^>\s]+>"#, .url),
    ]

    // Applied after the others, so nothing inside code is styled as anything else
    private static let codeRules = [
        Rule(#"^ {0,3}(```|~~~).*\n[\s\S]*?^ {0,3}\1[ \t]*$|^ {0,3}(?:```|~~~)[\s\S]*"#, .code),
        Rule(#"(`+)(?!`)[^\n]*?(?<!`)\1(?!`)"#, .code),
    ]

    public static func applies(to file: URL) -> Bool {
        fileExtensions.contains(file.pathExtension.lowercased())
    }

    public static func spans(in text: String) -> [Span] {
        let all = NSRange(location: 0, length: (text as NSString).length)
        var code: [NSRange] = []
        for rule in codeRules {
            let found = code
            code += rule.regex.matches(in: text, range: all).map(\.range).filter { !overlaps($0, found) }
            code.sort { $0.location < $1.location }
        }
        let spans = rules.flatMap { rule in
            rule.regex.matches(in: text, range: all).compactMap { match -> Span? in
                let range = match.range(at: rule.group)
                guard range.length > 0, !overlaps(range, code) else { return nil }
                return Span(range: range, style: rule.style)
            }
        }
        return spans + code.map { Span(range: $0, style: .code) }
    }

    /// `sorted` must be ordered by location and not overlap itself.
    private static func overlaps(_ range: NSRange, _ sorted: [NSRange]) -> Bool {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if NSMaxRange(sorted[middle]) <= range.location {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low < sorted.count && sorted[low].location < NSMaxRange(range)
    }
}
