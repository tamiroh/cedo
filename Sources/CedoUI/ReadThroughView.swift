import CedoKit
import SwiftUI

/// The files of a folder one after another, to read the writing as a whole.
struct ReadThroughView: View {
    private struct Section: Identifiable {
        let file: URL
        let text: String
        var id: URL { file }
    }

    @EnvironmentObject private var workspace: Workspace
    let folder: URL
    let horizontalInset: CGFloat
    @State private var savedTexts: [URL: (date: Date?, text: String?)] = [:]
    @State private var files: [URL] = []

    /// The open file is shown as it is being written, ahead of what is saved.
    private var sections: [Section] {
        files.compactMap { file in
            if workspace.selectedFile == file, let document = workspace.document {
                return Section(file: file, text: document.text)
            }
            return savedTexts[file]?.text.map { Section(file: file, text: $0) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    divider(for: section.file)
                        .padding(.top, index == 0 ? 0 : 40)
                        .padding(.bottom, 16)
                    Text(highlighted(section.text, by: workspace.configuration))
                        .font(.system(size: 13, design: .monospaced))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .task {
            while !Task.isCancelled {
                reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func divider(for file: URL) -> some View {
        HStack(spacing: 10) {
            Text(file.lastPathComponent)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Rectangle().fill(Theme.border).frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { workspace.select(file) }
        .help("Double-click to open \(file.lastPathComponent)")
    }

    private func reload() {
        let node = FileNode(url: folder, includesHiddenFiles: workspace.ui.showsHiddenFiles)
        files = node.readThroughFiles?.map(\.url) ?? []
        for file in files {
            // A fresh URL each time, as a URL caches the resource values it has read
            let date = try? URL(fileURLWithPath: file.path).resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
            if let saved = savedTexts[file], saved.date == date { continue }
            let text = (try? Data(contentsOf: file)).flatMap { String(data: $0, encoding: .utf8) }
            savedTexts[file] = (date, text)
        }
    }
}
