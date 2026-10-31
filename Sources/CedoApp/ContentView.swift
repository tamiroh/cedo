import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var dragStartWidth: CGFloat?
    @State private var editorWidth: CGFloat = 0
    @State private var columnDragStartWidth: CGFloat?

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
                    .frame(width: workspace.ui.panelWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.inset)
                    .overlay(alignment: .leading) { panelResizeHandle }
            }
        }
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .background { hiddenFilesShortcut }
        .ignoresSafeArea()
        .frame(minWidth: 700, minHeight: 400)
    }

    /// ⌘⇧. as in the Finder, kept out of the menus on purpose.
    private var hiddenFilesShortcut: some View {
        Button("") { workspace.toggleHiddenFiles() }
            .keyboardShortcut(".", modifiers: [.command, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
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
        let margin = textMargin
        VStack(alignment: .leading, spacing: 0) {
            if let file = workspace.selectedFile {
                header(for: file)
                    .padding(.horizontal, CodeTextView.textInset.width)
                if workspace.ui.showsHistory {
                    HistoryView(file: file, refreshKey: workspace.historyVersion)
                        .id(file)
                        .padding([.horizontal, .bottom], CodeTextView.textInset.width)
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
                        configuration: workspace.configuration, horizontalInset: margin,
                        onChange: workspace.textDidChange
                    )
                    .overlay { columnHandles(margin: margin) }
                }
            } else {
                Text(workspace.root == nil ? "No folder open. Press ⌘O to open one." : "No file selected.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, margin)
            }
        }
        .padding(.top, 36)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            editorWidth = $0
        }
    }

    private var textMargin: CGFloat {
        let minimum = CodeTextView.textInset.width
        guard let columns = workspace.ui.textColumns else { return minimum }
        let width = CGFloat(columns) * CodeTextView.characterWidth + 1
        return max(minimum, ((editorWidth - width) / 2).rounded(.down))
    }

    private func columnHandles(margin: CGFloat) -> some View {
        HStack(spacing: 0) {
            columnHandle(direction: -1)
                .padding(.leading, margin - 20)
            Spacer()
            columnHandle(direction: 1)
                .padding(.trailing, margin - 20)
        }
        .overlay(alignment: .top) {
            if columnDragStartWidth != nil {
                Text(workspace.ui.textColumns.map { "\($0) characters per line" } ?? "Fit to window")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Theme.selected))
                    .padding(.top, 8)
            }
        }
    }

    private func columnHandle(direction: CGFloat) -> some View {
        ColumnHandle(isDragging: columnDragStartWidth != nil) { translation in
            let minimum = CodeTextView.textInset.width
            let start = columnDragStartWidth ?? editorWidth - 2 * textMargin
            columnDragStartWidth = start
            let width = start + 2 * direction * translation
            let columns = Int((width / CodeTextView.characterWidth).rounded())
            if CGFloat(columns) * CodeTextView.characterWidth >= editorWidth - 2 * minimum {
                workspace.ui.textColumns = nil
            } else {
                workspace.ui.textColumns = max(columns, 10)
            }
        } onEnd: {
            columnDragStartWidth = nil
        } onReset: {
            workspace.ui.textColumns = nil
        }
    }

    private func panel(_ panel: UIState.Panel) -> some View {
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
                                let start = dragStartWidth ?? workspace.ui.panelWidth
                                dragStartWidth = start
                                workspace.ui.panelWidth = min(max(start - value.translation.width, 240), 900)
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
                tab("Edit", isActive: !workspace.ui.showsHistory) { workspace.ui.showsHistory = false }
                tab("History", isActive: workspace.ui.showsHistory) { workspace.ui.showsHistory = true }
            }
            .padding(.leading, 8)
        }
        .frame(height: Self.headerHeight)
        .padding(.bottom, 12)
    }

    private func tab(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        TabButton(title: title, isActive: isActive, action: action)
    }

    private func directory(of file: URL) -> String {
        guard let root = workspace.root else { return "" }
        let rootPath = root.url.standardizedFileURL.path
        let dirPath = file.deletingLastPathComponent().standardizedFileURL.path
        guard dirPath.hasPrefix(rootPath + "/") else { return root.name }
        return String(dirPath.dropFirst(rootPath.count + 1))
    }
}

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

private struct ColumnHandle: View {
    let isDragging: Bool
    let onDrag: (CGFloat) -> Void
    let onEnd: () -> Void
    let onReset: () -> Void
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || isDragging ? Theme.border : .clear)
            .frame(width: 1)
            .frame(width: 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .onTapGesture(count: 2, perform: onReset)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { onDrag($0.translation.width) }
                    .onEnded { _ in onEnd() }
            )
    }
}
