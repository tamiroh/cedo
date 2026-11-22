import AppKit
import CedoKit
import SwiftUI

struct ProjectSearchView: View {
    let folder: URL
    let includesHiddenFiles: Bool
    let open: (SearchHit) -> Void
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var completedQuery: String?
    @State private var hits: [SearchHit] = []
    @State private var selected = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Find in Files").font(.headline)
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            SearchField(query: $query, move: move, submit: openSelected, cancel: { dismiss() })
                .frame(height: 26)
            if completedQuery == query, !hits.isEmpty {
                HStack(spacing: 0) {
                    results.frame(width: 280)
                    Divider()
                    preview(hits[selected])
                }
                .frame(maxHeight: .infinity)
                HStack {
                    Text(
                        hits.count == ProjectSearch.limit
                            ? "Showing first \(hits.count) matches" : "\(hits.count) matches"
                    )
                    .foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Open in Editor", action: openSelected)
                }
            } else {
                Text(
                    query.isEmpty
                        ? "Search the text in this folder." : completedQuery == query ? "No matches." : "Searching…"
                )
                .foregroundStyle(Theme.muted)
                Spacer()
            }
        }
        .padding(16)
        .frame(width: 680, height: 390)
        .background(Theme.background)
        .task(id: query) {
            let term = query
            guard !term.isEmpty else {
                hits = []
                completedQuery = nil
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(150))
                let matches = try await ProjectSearch.find(
                    term, in: folder, includesHiddenFiles: includesHiddenFiles,
                    openFile: workspace.selectedFile, openText: workspace.text)
                try Task.checkCancellation()
                selected = 0
                hits = matches
                completedQuery = term
            } catch {}
        }
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(hits.indices, id: \.self) { index in
                        let hit = hits[index]
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(relativePath(hit.file)):\(hit.line)")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)
                                .truncationMode(.head)
                            Text(verbatim: hit.snippet)
                        }
                        .lineLimit(1)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(index == selected ? Theme.selection : .clear)
                        .contentShape(Rectangle())
                        .onTapGesture { selected = index }
                        .accessibilityAddTraits(.isButton)
                        .id(index)
                    }
                }
            }
            .onChange(of: selected) { proxy.scrollTo(selected) }
        }
    }

    private func preview(_ hit: SearchHit) -> some View {
        let source = hit.source as NSString
        let context = hit.previewRange
        var match = AttributedString(source.substring(with: hit.range))
        match.backgroundColor = Theme.selection
        let before = NSRange(location: context.location, length: hit.range.location - context.location)
        let after = NSRange(location: NSMaxRange(hit.range), length: NSMaxRange(context) - NSMaxRange(hit.range))
        let excerpt =
            AttributedString(source.substring(with: before)) + match + AttributedString(source.substring(with: after))
        return ScrollView {
            Text(excerpt)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxWidth: .infinity)
        .id(hit.range.location.description + hit.file.path)
    }

    private func relativePath(_ file: URL) -> String {
        file.pathComponents.dropFirst(folder.pathComponents.count).joined(separator: "/")
    }

    private func move(_ offset: Int) {
        guard completedQuery == query, !hits.isEmpty else { return }
        selected = min(max(0, selected + offset), hits.count - 1)
    }

    private func openSelected() {
        guard completedQuery == query, hits.indices.contains(selected) else { return }
        open(hits[selected])
    }
}

private struct SearchField: NSViewRepresentable {
    @Binding var query: String
    let move: (Int) -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(field: self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search project"
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.field = self
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var field: SearchField

        init(field: SearchField) { self.field = field }

        func controlTextDidChange(_ notification: Notification) {
            guard let input = notification.object as? NSSearchField else { return }
            field.query = input.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch command {
            case #selector(NSResponder.moveUp(_:)): field.move(-1)
            case #selector(NSResponder.moveDown(_:)): field.move(1)
            case #selector(NSResponder.insertNewline(_:)): field.submit()
            case #selector(NSResponder.cancelOperation(_:)): field.cancel()
            default: return false
            }
            return true
        }
    }

}
