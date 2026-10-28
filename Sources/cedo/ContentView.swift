import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: Workspace

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
            Button("Open Folder…") { workspace.promptForFolder() }
                .buttonStyle(OutlineButtonStyle())
                .padding(.top, 16)
                .padding(.bottom, 8)
            if let root = workspace.root {
                FileTreeView(root: root)
                    .id(root.url)
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
                if let message = workspace.errorMessage {
                    Text(message)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                } else {
                    CodeTextView(text: workspace.text, onChange: workspace.textDidChange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                }
            } else {
                Text(workspace.root == nil ? "No folder open." : "No file selected.")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 36)
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
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
        }
        .padding(.bottom, 24)
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
