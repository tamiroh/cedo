import Foundation

/// A folder's cedo settings, read from `.cedo.json` in its root:
///
///     { "highlights": [{ "pattern": "TODO", "color": "#e5c07b", "background": "#3a3220" }] }
public struct Configuration {
    /// A pattern to color in the text.
    public struct Highlight {
        public let regex: NSRegularExpression
        /// Colors as 0xRRGGBB.
        public let color: UInt32?
        public let background: UInt32?
    }

    public struct HighlightMatch: Equatable {
        /// In UTF-16 code units, as in `NSString`.
        public let range: NSRange
        /// The index of the matching pattern in `highlights`.
        public let highlight: Int
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    public static let fileName = ".cedo.json"

    /// Tells one loaded version of the settings from another.
    public let id = UUID()
    public let highlights: [Highlight]

    public static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName)
    }

    init(data: Data) throws {
        struct File: Decodable {
            let highlights: [HighlightEntry]?
        }
        struct HighlightEntry: Decodable {
            let pattern: String
            let color: String?
            let background: String?
        }

        let file: File
        do {
            file = try JSONDecoder().decode(File.self, from: data)
        } catch {
            throw Failure(message: "\(Self.fileName) is not valid JSON.")
        }
        highlights = try (file.highlights ?? []).map { entry in
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: entry.pattern, options: [.anchorsMatchLines])
            } catch {
                throw Failure(message: "Invalid pattern \"\(entry.pattern)\" in \(Self.fileName).")
            }
            return Highlight(
                regex: regex, color: try Self.color(entry.color), background: try Self.color(entry.background))
        }
    }

    /// Reads the settings file in the folder, or returns nil if there is none.
    public init?(root: URL) throws {
        guard let data = try? Data(contentsOf: Self.url(in: root)) else { return nil }
        try self.init(data: data)
    }

    public func highlightMatches(in text: String) -> [HighlightMatch] {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return highlights.enumerated().flatMap { index, highlight in
            highlight.regex.matches(in: text, range: range)
                .filter { $0.range.length > 0 }
                .map { HighlightMatch(range: $0.range, highlight: index) }
        }
    }

    private static func color(_ hex: String?) throws -> UInt32? {
        guard let hex else { return nil }
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            throw Failure(message: "Invalid color \"\(hex)\" in \(fileName). Use the form #RRGGBB.")
        }
        return value
    }
}
