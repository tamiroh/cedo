import CedoKit
import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject private var workspace: Workspace
    let root: FileNode
    @State private var expanded: Set<URL> = []

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    FileRow(
                        row: row,
                        isExpanded: expanded.contains(row.id),
                        isSelected: workspace.selectedFile == row.id,
                        editedCount: workspace.selectedFile == row.id
                            ? workspace.document.map { CharacterCount.of($0.text) } : nil
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

private struct FileRow: View {
    let row: Row
    let isExpanded: Bool
    let isSelected: Bool
    /// The count of the text open in the editor, which can be ahead of the file.
    let editedCount: Int?
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
                if !row.node.isDirectory, let count = editedCount ?? savedCount {
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
        // Counted again once the file is no longer open, as it was saved on leaving
        .task(id: CountKey(node: row.node, isEdited: editedCount != nil)) {
            guard !row.node.isDirectory, editedCount == nil else { return }
            let file = row.node.url
            savedCount = await Task.detached { CharacterCount.of(file: file) }.value
        }
    }

    private struct CountKey: Hashable {
        let node: FileNode
        let isEdited: Bool
    }
}
