import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var panelWidth: CGFloat = 440
    @State private var dragStartWidth: CGFloat?
    @State private var showsHistory = false

    /// The header row, shared by the editor and the panel so their tabs line up.
    private static let headerHeight: CGFloat = 24

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 260)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.inset)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.border).frame(width: 1)
                }
            main
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if let panel = workspace.panel {
                self.panel(panel)
                    .padding(.top, 36)
                    .padding([.leading, .bottom], 12)
                    .frame(width: panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.inset)
                    .overlay(alignment: .leading) { panelResizeHandle }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .ignoresSafeArea()
        .frame(minWidth: 700, minHeight: 400)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(workspace.root?.name ?? "cedo")
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8)
            if let root = workspace.root {
                FileTreeView(root: root)
                    .id(root.url)
                    .padding(.top, 12)
            }
        }
        // Leave room for the window's traffic-light buttons
        .padding(.top, 40)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var main: some View {
        let margin = CodeTextView.textInset.width
        VStack(alignment: .leading, spacing: 0) {
            if let file = workspace.selectedFile {
                header(for: file)
                    .padding(.horizontal, margin)
                if showsHistory {
                    HistoryView(file: file, refreshKey: workspace.historyVersion)
                        .id(file)
                        .padding([.horizontal, .bottom], margin)
                        .padding(.top, 12)
                } else if let message = workspace.errorMessage {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, margin)
                        .padding(.top, 12)
                } else {
                    CodeTextView(
                        text: workspace.text, document: file, lint: workspace.lint,
                        configuration: workspace.configuration,
                        onChange: workspace.textDidChange)
                }
            } else {
                Text(workspace.root == nil ? "No folder open. Press ⌘O to open one." : "No file selected.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, margin)
            }
        }
        .padding(.top, 36)
    }

    private func panel(_ panel: Workspace.Panel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 2) {
                tab("Terminal", isActive: panel == .terminal) { workspace.show(.terminal) }
                    .disabled(workspace.root == nil)
                tab("Log", isActive: panel == .log) { workspace.show(.log) }
            }
            .frame(height: Self.headerHeight)
            switch panel {
            case .terminal:
                if let shell = workspace.shell {
                    TerminalPanel(session: shell)
                        .padding(.trailing, 8)
                }
            case .log:
                LogView(log: workspace.log)
            }
        }
    }

    /// The panel's left border, which can be dragged to resize it.
    private var panelResizeHandle: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(width: 1)
            .overlay {
                Color.clear
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                let start = dragStartWidth ?? panelWidth
                                dragStartWidth = start
                                panelWidth = min(max(start - value.translation.width, 240), 900)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
    }

    private func header(for file: URL) -> some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(file.lastPathComponent)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Text(directory(of: file))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 16)
            if workspace.saveFailed {
                Text("Couldn't save")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
            }
            HStack(spacing: 2) {
                tab("Edit", isActive: !showsHistory) { showsHistory = false }
                tab("History", isActive: showsHistory) { showsHistory = true }
            }
            .padding(.leading, 8)
        }
        .frame(height: Self.headerHeight)
        .padding(.bottom, 12)
    }

    private func tab(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        TabButton(title: title, isActive: isActive, action: action)
    }

    /// The file's folder relative to the project root, or the root's name for top-level files.
    private func directory(of file: URL) -> String {
        guard let root = workspace.root else { return "" }
        let rootPath = root.url.standardizedFileURL.path
        let dirPath = file.deletingLastPathComponent().standardizedFileURL.path
        guard dirPath.hasPrefix(rootPath + "/") else { return root.name }
        return String(dirPath.dropFirst(rootPath.count + 1))
    }
}

/// A tab marked like a selected row in the file tree.
private struct TabButton: View {
    let title: String
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Theme.text : Theme.muted)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Theme.selected : hovering ? Theme.surface : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
