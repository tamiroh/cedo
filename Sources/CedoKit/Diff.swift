import Foundation

/// A unified diff read into hunks, without the headers.
public struct Diff: Equatable {
    public struct Hunk: Equatable {
        /// The hunk's first line in the new version.
        public let line: Int
        public var lines: [Line]
    }

    public struct Line: Equatable {
        public enum Kind { case context, added, removed }

        public let kind: Kind
        public let text: String
        /// For a rewritten line, the characters that differ from its counterpart.
        public var changed: Range<Int>?
    }

    public private(set) var hunks: [Hunk] = []

    public init(parsing patch: String) {
        for line in patch.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("@@") {
                hunks.append(Hunk(line: Self.newStart(in: line) ?? 1, lines: []))
                continue
            }
            guard !hunks.isEmpty, let kind = line.first else { continue }
            let text = String(line.dropFirst())
            switch kind {
            case " ": hunks[hunks.count - 1].lines.append(Line(kind: .context, text: text))
            case "+": hunks[hunks.count - 1].lines.append(Line(kind: .added, text: text))
            case "-": hunks[hunks.count - 1].lines.append(Line(kind: .removed, text: text))
            default: break
            }
        }
        for index in hunks.indices {
            Self.markRewrites(in: &hunks[index].lines)
        }
    }

    /// The differing middles of two strings, between their common prefix and suffix, in characters.
    public static func changedRanges(_ old: String, _ new: String) -> (old: Range<Int>, new: Range<Int>) {
        let old = Array(old)
        let new = Array(new)
        var start = 0
        while start < min(old.count, new.count), old[start] == new[start] { start += 1 }
        var end = 0
        while end < min(old.count, new.count) - start, old[old.count - 1 - end] == new[new.count - 1 - end] {
            end += 1
        }
        return (start..<old.count - end, start..<new.count - end)
    }

    private static func newStart(in header: Substring) -> Int? {
        guard let plus = header.split(separator: " ").first(where: { $0.hasPrefix("+") }) else { return nil }
        return Int(plus.dropFirst().prefix { $0 != "," })
    }

    /// Pairs each block of removed lines with the added lines after it, and marks what changed within each pair.
    private static func markRewrites(in lines: inout [Line]) {
        var index = 0
        while index < lines.count {
            let removed = lines[index...].prefix { $0.kind == .removed }.count
            let added = lines[(index + removed)...].prefix { $0.kind == .added }.count
            for offset in 0..<min(removed, added) {
                let old = index + offset
                let new = index + removed + offset
                let ranges = changedRanges(lines[old].text, lines[new].text)
                // Marking the whole line would say nothing the color doesn't
                guard ranges.old.count < lines[old].text.count || ranges.new.count < lines[new].text.count else {
                    continue
                }
                lines[old].changed = ranges.old
                lines[new].changed = ranges.new
            }
            index += max(removed + added, 1)
        }
    }
}
