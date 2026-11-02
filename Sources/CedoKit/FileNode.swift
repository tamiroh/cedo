import Foundation

public final class FileNode: Identifiable, Hashable {
    /// Files and folders of tools rather than of the writing, such as a textlint setup's dependencies.
    /// Hidden like dotfiles, and never counted or read through.
    public static let toolNames: Set<String> = [
        ".build", ".git", ".venv", "DerivedData", "Pods", "__pycache__", "bun.lock", "bun.lockb", "node_modules",
        "package-lock.json", "package.json", "pnpm-lock.yaml", "venv", "yarn.lock",
    ]

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
        return urls.filter {
            $0.lastPathComponent != ".git" && (includesHiddenFiles || !Self.toolNames.contains($0.lastPathComponent))
        }.map {
            FileNode(url: $0, includesHiddenFiles: includesHiddenFiles)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }()

    /// The files to read through one after another, or nil for a folder with subfolders, which reading
    /// through does not cover yet. Hidden folders and those of tools don't count as subfolders.
    public var readThroughFiles: [FileNode]? {
        guard let children = children?.filter({ !Self.toolNames.contains($0.name) }) else { return nil }
        let files = children.filter { !$0.isDirectory }
        let hasSubfolders = children.contains { $0.isDirectory && !$0.name.hasPrefix(".") }
        return hasSubfolders || files.isEmpty ? nil : files
    }

    // Compared by identity, so a freshly read tree always counts as a change and SwiftUI redraws it
    public static func == (lhs: FileNode, rhs: FileNode) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
