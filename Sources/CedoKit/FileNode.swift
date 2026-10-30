import Foundation

/// A node in the file tree. Children are loaded the first time they are accessed.
public final class FileNode: Identifiable, Hashable {
    public let url: URL
    public let isDirectory: Bool
    public let includesHiddenFiles: Bool

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, includesHiddenFiles: Bool = false) {
        self.url = url
        self.includesHiddenFiles = includesHiddenFiles
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        self.isDirectory = values?.isDirectory ?? false
    }

    /// Child nodes (directories first, then by name) for a directory, or nil for a file.
    public lazy var children: [FileNode]? = {
        guard isDirectory else { return nil }
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: includesHiddenFiles ? [] : [.skipsHiddenFiles]
            )) ?? []
        // .git stays out of sight even with hidden files shown
        return urls.filter { $0.lastPathComponent != ".git" }.map {
            FileNode(url: $0, includesHiddenFiles: includesHiddenFiles)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }()

    // Compared by identity, so a freshly read tree always counts as a change and SwiftUI redraws it
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
