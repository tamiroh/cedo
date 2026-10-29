import SwiftUI

/// The Git history of one file: its commits on the left, and the selected commit's diff on the right.
struct HistoryView: View {
    let file: URL
    /// Changing this reloads the history, e.g. after an auto-commit.
    let refreshKey: Int
    @State private var commits: Loadable<[Commit]> = .loading
    @State private var selected: Commit?
    @State private var diff: Loadable<String> = .loading

    var body: some View {
        Group {
            switch commits {
            case .loading:
                message("Loading…")
            case .failed(let error):
                message(error)
            case .loaded(let commits) where commits.isEmpty:
                message("No commits for this file yet.")
            case .loaded(let commits):
                HStack(alignment: .top, spacing: 16) {
                    commitList(commits)
                        .frame(width: 280)
                    diffPane
                }
            }
        }
        .task(id: refreshKey) { await load() }
    }

    private func commitList(_ commits: [Commit]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commits) { commit in
                    CommitRow(commit: commit, isSelected: commit == selected) {
                        Task { await select(commit) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var diffPane: some View {
        Group {
            switch diff {
            case .loading:
                message("Loading…").padding(12)
            case .failed(let error):
                message(error).padding(12)
            case .loaded(let text) where text.isEmpty:
                message("No changes to show.").padding(12)
            case .loaded(let text):
                DiffText(text: text)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.inset)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        do {
            let result = try await Git.history(of: file)
            commits = .loaded(result)
            if let first = result.first {
                await select(first)
            }
        } catch {
            commits = .failed(error.localizedDescription)
        }
    }

    private func select(_ commit: Commit) async {
        selected = commit
        diff = .loading
        let result: Loadable<String>
        do {
            result = .loaded(try await Git.diff(of: commit, near: file))
        } catch {
            result = .failed(error.localizedDescription)
        }
        // Drop the result if another commit was selected in the meantime
        if selected == commit {
            diff = result
        }
    }
}

private enum Loadable<Value> {
    case loading
    case loaded(Value)
    case failed(String)
}

private struct CommitRow: View {
    let commit: Commit
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(commit.shortHash) · \(commit.author) · \(commit.date)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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

private struct DiffText: View {
    let text: String

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    let line = lines[index]
                    Text(line.isEmpty ? " " : String(line))
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(color(for: line))
                        .frame(minHeight: 20, alignment: .leading)
                        .fixedSize()
                }
            }
            .padding(12)
            .textSelection(.enabled)
        }
    }

    private func color(for line: Substring) -> Color {
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") {
            return Theme.muted
        }
        if line.hasPrefix("@@") { return Theme.hunk }
        if line.hasPrefix("+") { return Theme.added }
        if line.hasPrefix("-") { return Theme.removed }
        return Theme.text
    }
}
