import CedoKit
import SwiftUI

struct HistoryView: View {
    let file: URL
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
                    .lineLimit(isSelected ? nil : 1)
                    .fixedSize(horizontal: false, vertical: isSelected)
                HStack(spacing: 6) {
                    Text(Self.timestamp(of: commit.date))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if commit.added > 0 {
                        Text("+\(commit.added)").foregroundStyle(Theme.added)
                    }
                    if commit.removed > 0 {
                        Text("−\(commit.removed)").foregroundStyle(Theme.removed)
                    }
                }
                .font(.system(size: 12).monospacedDigit())
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

    static func timestamp(of date: Date, now: Date = .now) -> String {
        let format: Date.FormatString =
            Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
            ? "\(month: .defaultDigits)/\(day: .defaultDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
            : "\(year: .defaultDigits)/\(month: .twoDigits)/\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
        let absolute = date.formatted(.verbatim(format, timeZone: .current, calendar: .current))
        let relative = date.formatted(.relative(presentation: .numeric).locale(Locale(identifier: "en_US")))
        return "\(absolute) · \(relative)"
    }
}

private struct DiffText: View {
    let diff: Diff

    init(text: String) {
        diff = Diff(parsing: text)
    }

    private enum Row {
        case hunk(line: Int, isFirst: Bool)
        case line(Diff.Line)
    }

    /// One flat list, so every row has its own position as its identity.
    private var rows: [Row] {
        diff.hunks.enumerated().flatMap { index, hunk in
            [Row.hunk(line: hunk.line, isFirst: index == 0)] + hunk.lines.map(Row.line)
        }
    }

    var body: some View {
        let rows = rows
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { index in
                    switch rows[index] {
                    case .hunk(let line, let isFirst):
                        Text("Line \(line)")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.muted)
                            .padding(.top, isFirst ? 0 : 16)
                            .padding(.bottom, 4)
                            .padding(.horizontal, 12)
                    case .line(let line):
                        self.line(line)
                    }
                }
            }
            .padding(.vertical, 12)
            .textSelection(.enabled)
        }
    }

    private func line(_ line: Diff.Line) -> some View {
        Text(attributed(line))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(line.kind == .context ? Theme.muted : Theme.text)
            .lineSpacing(3)
            .padding(.vertical, 2)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint(of: line).opacity(0.12))
            .overlay(alignment: .leading) {
                Rectangle().fill(tint(of: line)).frame(width: 2)
            }
    }

    private func attributed(_ line: Diff.Line) -> AttributedString {
        let characters = Array(line.text.isEmpty ? " " : line.text)
        guard let changed = line.changed else { return AttributedString(String(characters)) }
        var middle = AttributedString(String(characters[changed]))
        middle.backgroundColor = tint(of: line).opacity(0.35)
        return AttributedString(String(characters[..<changed.lowerBound])) + middle
            + AttributedString(String(characters[changed.upperBound...]))
    }

    private func tint(of line: Diff.Line) -> Color {
        switch line.kind {
        case .context: .clear
        case .added: Theme.added
        case .removed: Theme.removed
        }
    }
}
