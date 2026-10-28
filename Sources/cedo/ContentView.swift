import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: Workspace
    @State private var terminalWidth: CGFloat = 440
    @State private var dragStartWidth: CGFloat?
    @State private var showsHistory = false

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
            if workspace.isTerminalVisible, let shell = workspace.shell {
                TerminalPanel(session: shell)
                    .padding(.top, 36)
                    .padding([.leading, .bottom], 12)
                    .padding(.trailing, 8)
                    .frame(width: terminalWidth)
                    .frame(maxHeight: .infinity)
                    .background(Theme.inset)
                    .overlay(alignment: .leading) { terminalResizeHandle }
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
        VStack(alignment: .leading, spacing: 0) {
            if let file = workspace.selectedFile {
                header(for: file)
                if showsHistory {
                    HistoryView(file: file)
                        .id(file)
                } else if let message = workspace.errorMessage {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                } else {
                    CodeTextView(text: workspace.text, onChange: workspace.textDidChange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                }
            } else {
                Text(workspace.root == nil ? "No folder open. Press ⌘O to open one." : "No file selected.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 36)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    /// The terminal's left border, which can be dragged to resize the panel.
    private var terminalResizeHandle: some View {
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
                                let start = dragStartWidth ?? terminalWidth
                                dragStartWidth = start
                                terminalWidth = min(max(start - value.translation.width, 240), 900)
                            }
                            .onEnded { _ in dragStartWidth = nil }
                    )
            }
    }

    private func header(for file: URL) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(file.lastPathComponent)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
            Text(directory(of: file))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 16)
            if workspace.errorMessage == nil {
                Text(workspace.isDirty ? "Unsaved" : "Saved")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            HStack(spacing: 14) {
                tab("Edit", isActive: !showsHistory) { showsHistory = false }
                tab("History", isActive: showsHistory) { showsHistory = true }
            }
            .padding(.leading, 8)
        }
        .padding(.bottom, 24)
    }

    private func tab(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(isActive ? Theme.text : Theme.muted)
                .padding(.bottom, 1)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(isActive ? Theme.text : .clear)
                        .frame(height: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
