import Foundation

/// Counts characters the way manuscripts usually are: every visible character, leaving out spaces and line breaks.
public enum CharacterCount {
    private static let maxFileSize = 5 * 1024 * 1024

    public static func of(_ text: String) -> Int {
        text.reduce(0) { $1.isWhitespace || $1 == "\u{FEFF}" ? $0 : $0 + 1 }
    }

    /// Nil for files that are not UTF-8 text, or too large to read quickly.
    public static func of(file: URL) -> Int? {
        let file = file.resolvingSymlinksInPath()
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maxFileSize,
            let data = try? Data(contentsOf: file), !data.contains(0),
            let text = String(data: data, encoding: .utf8)
        else { return nil }
        return of(text)
    }
}
