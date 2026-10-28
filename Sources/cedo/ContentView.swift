import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 220)
        } detail: {
            detail
        }
        .navigationTitle(title)
        .frame(minWidth: 700, minHeight: 400)
    }

    @ViewBuilder
    private var sidebar: some View {
        if let root = workspace.root {
            List(selection: Binding(
                get: { workspace.selectedFile },
                set: { workspace.select($0) }
            )) {
                OutlineGroup(root.children ?? [], children: \.children) { node in
                    Label(node.name, systemImage: node.isDirectory ? "folder" : "doc")
                        .tag(node.url)
                }
            }
            .listStyle(.sidebar)
        } else {
            Button("Open Folder…") { workspace.promptForFolder() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let message = workspace.errorMessage {
            Text(message)
                .foregroundStyle(.secondary)
        } else if workspace.selectedFile != nil {
            CodeTextView(text: workspace.text, onChange: workspace.textDidChange)
        } else {
            Text("No file selected")
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        guard let root = workspace.root else { return "cedo" }
        guard let file = workspace.selectedFile else { return root.name }
        return file.lastPathComponent + (workspace.isDirty ? " •" : "")
    }
}
