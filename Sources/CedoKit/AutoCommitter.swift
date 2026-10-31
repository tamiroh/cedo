import Foundation

/// Commits saved files when the writer pauses, so each commit is roughly one burst of writing.
///
/// A pause is a few idle minutes after saving, switching to another file or folder, or quitting.
/// Only files saved in cedo are committed; other changes in the repository are left alone.
public final class AutoCommitter {
    private static let idleDelay: TimeInterval = 5 * 60

    /// Called on the main thread after a commit has been made.
    public var onCommit: (() -> Void)?

    // Accessed on the main thread only
    private var pending: Set<URL> = []
    private var idleTimer: DispatchWorkItem?

    // Runs commits one at a time so git never races itself for the index lock
    private let queue = DispatchQueue(label: "cedo.auto-commit")
    private let log: DebugLog

    public init(log: DebugLog) {
        self.log = log
    }

    public func fileSaved(_ file: URL) {
        pending.insert(file)
        restartIdleTimer()
    }

    /// Typing pushes the pause further out, as long as something is waiting to be committed.
    public func textChanged() {
        if !pending.isEmpty {
            restartIdleTimer()
        }
    }

    /// Commits everything saved so far.
    public func flush() {
        flush(summarizing: true)
    }

    /// Commits everything saved so far and waits until the commits are done. Skips the generated summary,
    /// so quitting never waits on the model.
    public func flushAndWait() {
        flush(summarizing: false)
        queue.sync {}
    }

    private func flush(summarizing: Bool) {
        idleTimer?.cancel()
        idleTimer = nil
        guard !pending.isEmpty else { return }
        let files = pending
        pending = []
        let onCommit = onCommit
        let log = log
        queue.async {
            if Self.commit(files, summarizing: summarizing, log: log) {
                DispatchQueue.main.async { onCommit?() }
            }
        }
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in self?.flush() }
        idleTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDelay, execute: timer)
    }

    /// Commits the files, one commit per repository. Returns true if any commit was made.
    private static func commit(_ files: Set<URL>, summarizing: Bool, log: DebugLog) -> Bool {
        let byRepository = Dictionary(grouping: files) { try? Git.topLevel(of: $0) }
        var committed = false
        for (repository, files) in byRepository {
            guard let repository else {
                log.info("Not committing files outside a Git repository: " + names(files))
                continue
            }
            do {
                let sorted = files.sorted { $0.path < $1.path }
                if let message = try commit(sorted, in: repository, summarizing: summarizing) {
                    log.info("Committed in \(repository.lastPathComponent): \(message.prefix { $0 != "\n" })")
                    committed = true
                } else {
                    log.info("Nothing to commit: " + names(files))
                }
            } catch {
                log.error("Auto-commit failed in \(repository.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return committed
    }

    private static func names(_ files: [URL]) -> String {
        files.map(\.lastPathComponent).sorted().joined(separator: ", ")
    }

    /// Returns the commit message, or nil if no file differs from HEAD.
    private static func commit(_ files: [URL], in repository: URL, summarizing: Bool) throws -> String? {
        var changes: [Change] = []
        for file in files {
            let old = Git.headVersion(of: file) ?? ""
            guard let new = try? String(contentsOf: file, encoding: .utf8), new != old else { continue }
            changes.append(Change(file: file, characterDelta: new.count - old.count))
        }
        guard !changes.isEmpty else { return nil }

        let paths = changes.map(\.file.path)
        // `add` picks up new files; `--only` keeps anything else the user has staged out of this commit
        try Git.runSync(["add", "--"] + paths, in: repository)
        var summary: String?
        if summarizing {
            let diff = try Git.runSync(["diff", "--cached", "--no-color", "-U0", "--"] + paths, in: repository)
            summary = EditSummary.describe(diff: diff)
        }
        let message = message(for: changes, summary: summary)
        try Git.runSync(["commit", "--quiet", "--only", "-m", message, "--"] + paths, in: repository)
        return message
    }

    struct Change {
        let file: URL
        let characterDelta: Int
    }

    /// The summary, if there is one, followed by the files and how much each grew or shrank.
    static func message(for changes: [Change], summary: String? = nil) -> String {
        func describe(_ change: Change) -> String {
            let sign = change.characterDelta < 0 ? "-" : "+"
            return "\(change.file.lastPathComponent) (\(sign)\(abs(change.characterDelta)) chars)"
        }
        if let summary {
            return summary + "\n\n" + changes.map { "- " + describe($0) }.joined(separator: "\n")
        }
        if changes.count == 1 {
            return "Edit " + describe(changes[0])
        }
        return "Edit \(changes.count) files\n\n" + changes.map { "- " + describe($0) }.joined(separator: "\n")
    }
}
