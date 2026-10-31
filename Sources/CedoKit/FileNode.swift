import Foundation

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

    public lazy var children: [FileNode]? = {
        guard isDirectory else { return nil }
        let urls =
            (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: includesHiddenFiles ? [] : [.skipsHiddenFiles]
            )) ?? []
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
