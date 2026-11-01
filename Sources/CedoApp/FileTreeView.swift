import CedoKit
import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject private var workspace: Workspace
    let root: FileNode
    @State private var expanded: Set<URL> = []

    var body: some View {
        let openFile = workspace.selectedFile.flatMap { file in
            workspace.document.map { OpenFile(url: file, count: CharacterCount.of($0.text)) }
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    FileRow(
                        row: row,
                        isExpanded: expanded.contains(row.id),
                        isSelected: workspace.selectedFile == row.id,
                        openFile: openFile
                    ) {
                        if row.node.isDirectory {
                            toggle(row.id)
                        } else {
                            workspace.select(row.id)
                        }
                    }
                    .contextMenu {
                        Button("New File…") {
                            workspace.newFile(in: row.node.isDirectory ? row.id : row.id.deletingLastPathComponent())
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .contextMenu {
            Button("New File…") { workspace.newFile(in: root.url) }
        }
        .onAppear { expandFolders(containing: workspace.selectedFile) }
        .onChange(of: workspace.selectedFile) { expandFolders(containing: workspace.selectedFile) }
    }

    private var rows: [Row] {
        var result: [Row] = []
        func visit(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                result.append(Row(node: node, depth: depth))
                if expanded.contains(node.url) {
                    visit(node.children ?? [], depth: depth + 1)
                }
            }
        }
        visit(root.children ?? [], depth: 0)
        return result
    }

    private func expandFolders(containing file: URL?) {
        guard var folder = file?.deletingLastPathComponent().standardizedFileURL else { return }
        let rootPath = root.url.standardizedFileURL.path
        while folder.path.hasPrefix(rootPath + "/") {
            expanded.insert(folder)
            folder = folder.deletingLastPathComponent()
        }
    }

    private func toggle(_ url: URL) {
        if expanded.contains(url) {
            expanded.remove(url)
        } else {
            expanded.insert(url)
        }
    }
}

private struct Row: Identifiable {
    let node: FileNode
    let depth: Int
    var id: URL { node.url }
}

/// The file in the editor, counted from its text, which can be ahead of what is saved.
private struct OpenFile {
    let url: URL
    let count: Int
}

private struct FileRow: View {
    let row: Row
    let isExpanded: Bool
    let isSelected: Bool
    let openFile: OpenFile?
    let action: () -> Void
    @State private var hovering = false
    @State private var savedCount: Int?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 12)
                    .opacity(row.node.isDirectory ? 1 : 0)
                Text(row.node.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if let count {
                    Text(count.formatted())
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .layoutPriority(1)
                }
            }
            .padding(.vertical, 5)
            .padding(.leading, 4 + CGFloat(row.depth) * 12)
            .padding(.trailing, 8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Theme.selected : hovering ? Theme.surface : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // Counted again when the open file comes or goes, as it is saved on leaving
        .task(id: CountKey(node: row.node, openFile: openFileWithin?.url)) {
            let url = row.id
            let excluded = openFileWithin?.url
            if row.node.isDirectory {
                let includesHiddenFiles = row.node.includesHiddenFiles
                savedCount = await Task.detached {
                    CharacterCount.of(folder: url, includesHiddenFiles: includesHiddenFiles, excluding: excluded)
                }.value
            } else if excluded == nil {
                savedCount = await Task.detached { CharacterCount.of(file: url) }.value
            }
        }
    }

    /// The open file, if it is this file or inside this folder.
    private var openFileWithin: OpenFile? {
        guard let openFile else { return nil }
        let isWithin =
            row.node.isDirectory ? openFile.url.path.hasPrefix(row.id.path + "/") : openFile.url == row.id
        return isWithin ? openFile : nil
    }

    private var count: Int? {
        if !row.node.isDirectory, let openFileWithin {
            return openFileWithin.count
        }
        return savedCount.map { $0 + (openFileWithin?.count ?? 0) }
    }

    private struct CountKey: Hashable {
        let node: FileNode
        let openFile: URL?
    }
}
