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
                        isSelected: workspace.selectedFile == row.id
                    ) {
                        if row.node.isDirectory {
                            toggle(row.id)
                        } else {
                            workspace.select(row.id)
                        }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .onAppear { expandFolders(containing: workspace.selectedFile) }
    }

    /// The nodes currently visible, flattened in display order.
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

    /// Opens the folders down to a file, so a file restored at launch is visible in the tree.
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
    let action: () -> Void
    @State private var hovering = false

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
    }
}
