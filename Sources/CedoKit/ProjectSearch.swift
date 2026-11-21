import Foundation

public struct SearchHit: Sendable {
    public let file: URL
    public let source: String
    public let line: Int
    public let range: NSRange
    public let lineRange: NSRange

    public var snippet: String {
        let start = max(lineRange.location, range.location - 40)
        let end = min(NSMaxRange(lineRange), NSMaxRange(range) + 60)
        let text = source as NSString
        return text.substring(
            with: text.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var previewRange: NSRange {
        let text = source as NSString
        var start = lineRange.location
        var end = NSMaxRange(lineRange)
        for _ in 0..<4 {
            if start > 0 { start = text.lineRange(for: NSRange(location: start - 1, length: 1)).location }
            if end < text.length { end = NSMaxRange(text.lineRange(for: NSRange(location: end, length: 1))) }
        }
        return NSRange(location: start, length: end - start)
    }
}

public enum ProjectSearch {
    public static let limit = 500

    public static func find(
        _ query: String, in folder: URL, includesHiddenFiles: Bool, openFile: URL?, openText: String
    ) async throws -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        var hits: [SearchHit] = []
        let root = FileNode(url: folder, includesHiddenFiles: includesHiddenFiles)
        let openPath = openFile?.standardizedFileURL.path
        var pending = Array((root.children ?? []).reversed())
        while let node = pending.popLast() {
            try Task.checkCancellation()
            let info = try? node.url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard info?.isSymbolicLink != true else { continue }
            if node.isDirectory {
                await Task.yield()
                pending.append(contentsOf: (node.children ?? []).reversed())
            } else if info?.isRegularFile == true {
                let currentFile = node.url.standardizedFileURL.path == openPath ? openFile : nil
                guard let source = currentFile == nil ? Document(url: node.url)?.text : openText,
                    !source.utf8.contains(0)
                else { continue }
                try appendMatches(query, file: currentFile ?? node.url, source: source, to: &hits)
                if hits.count >= limit { break }
            }
        }
        return hits
    }

    private static func appendMatches(_ query: String, file: URL, source: String, to hits: inout [SearchHit]) throws {
        let text = source as NSString
        var start = 0
        var line = 1
        while start < text.length {
            try Task.checkCancellation()
            let lineRange = text.lineRange(for: NSRange(location: start, length: 0))
            let end = NSMaxRange(lineRange)
            while start < end {
                let range = text.range(
                    of: query, options: .caseInsensitive, range: NSRange(location: start, length: end - start))
                guard range.location != NSNotFound, range.length > 0 else { break }
                hits.append(SearchHit(file: file, source: source, line: line, range: range, lineRange: lineRange))
                if hits.count == limit { return }
                start = NSMaxRange(range)
            }
            start = end
            line += 1
        }
    }
}
