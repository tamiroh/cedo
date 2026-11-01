import Foundation
import os

/// Counts characters the way manuscripts usually are: every visible character, leaving out spaces and line breaks.
public enum CharacterCount {
    /// Folders of tools and dependencies, which are large and not part of the writing.
    static let skippedFolders: Set<String> = [
        ".build", ".git", ".venv", "DerivedData", "Pods", "__pycache__", "node_modules", "venv",
    ]
    private static let maxFileSize = 5 * 1024 * 1024
    private static let cache = OSAllocatedUnfairLock<[URL: (date: Date, count: Int?)]>(initialState: [:])

    public static func of(_ text: String) -> Int {
        text.reduce(0) { $1.isWhitespace || $1 == "\u{FEFF}" ? $0 : $0 + 1 }
    }

    /// Nil for files that are not UTF-8 text, or too large to read quickly.
    public static func of(file: URL) -> Int? {
        let file = file.resolvingSymlinksInPath()
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
            let size = values.fileSize, let date = values.contentModificationDate
        else { return nil }
        if let cached = cache.withLock({ $0[file] }), cached.date == date {
            return cached.count
        }
        let count = size <= maxFileSize ? read(file).map(of) : nil
        cache.withLock { $0[file] = (date, count) }
        return count
    }

    /// The total of the files in a folder and its subfolders, leaving out `excluded`.
    /// Nil for the folders of tools and dependencies.
    public static func of(folder: URL, includesHiddenFiles: Bool, excluding excluded: URL? = nil) -> Int? {
        guard !skippedFolders.contains(folder.lastPathComponent) else { return nil }
        let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey],
            options: includesHiddenFiles ? [] : [.skipsHiddenFiles]
        )
        var total = 0
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if skippedFolders.contains(url.lastPathComponent) {
                    enumerator?.skipDescendants()
                }
            } else if url.standardizedFileURL != excluded?.standardizedFileURL {
                total += of(file: url) ?? 0
            }
        }
        return total
    }

    private static func read(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file), !data.contains(0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
