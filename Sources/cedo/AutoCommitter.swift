import Foundation

/// Commits saved files when the writer pauses, so each commit is roughly one burst of writing.
///
/// A pause is a few idle minutes after saving, switching to another file or folder, or quitting.
/// Only files saved in cedo are committed; other changes in the repository are left alone.
final class AutoCommitter {
    private static let idleDelay: TimeInterval = 5 * 60

    /// Called on the main thread after a commit has been made.
    var onCommit: (() -> Void)?

    // Accessed on the main thread only
    private var pending: Set<URL> = []
    private var idleTimer: DispatchWorkItem?

    // Runs commits one at a time so git never races itself for the index lock
    private let queue = DispatchQueue(label: "cedo.auto-commit")

    func fileSaved(_ file: URL) {
        pending.insert(file)
        restartIdleTimer()
    }

    /// Typing pushes the pause further out, as long as something is waiting to be committed.
    func textChanged() {
        if !pending.isEmpty {
            restartIdleTimer()
        }
    }

    /// Commits everything saved so far.
    func flush() {
        idleTimer?.cancel()
        idleTimer = nil
        guard !pending.isEmpty else { return }
        let files = pending
        pending = []
        let onCommit = onCommit
        queue.async {
            if Self.commit(files) {
                DispatchQueue.main.async { onCommit?() }
            }
        }
    }

    /// Commits everything saved so far and waits until the commits are done.
    func flushAndWait() {
        flush()
        queue.sync {}
    }

    private func restartIdleTimer() {
        idleTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in self?.flush() }
        idleTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.idleDelay, execute: timer)
    }

    /// Commits the files, one commit per repository. Returns true if any commit was made.
    private static func commit(_ files: Set<URL>) -> Bool {
        // Files outside a Git repository are skipped
        let byRepository = Dictionary(grouping: files) { try? Git.topLevel(of: $0) }
        var committed = false
        for case let (repository?, files) in byRepository {
            do {
                if try commit(files.sorted { $0.path < $1.path }, in: repository) {
                    committed = true
                }
            } catch {
                NSLog("cedo: auto-commit failed in %@: %@", repository.path, error.localizedDescription)
            }
        }
        return committed
    }

    private static func commit(_ files: [URL], in repository: URL) throws -> Bool {
        var changes: [Change] = []
        for file in files {
            let old = Git.headVersion(of: file) ?? ""
            guard let new = try? String(contentsOf: file, encoding: .utf8), new != old else { continue }
            changes.append(Change(file: file, characterDelta: new.count - old.count))
        }
        guard !changes.isEmpty else { return false }

        let paths = changes.map(\.file.path)
        // `add` picks up new files; `--only` keeps anything else the user has staged out of this commit
        try Git.runSync(["add", "--"] + paths, in: repository)
        try Git.runSync(["commit", "--quiet", "--only", "-m", message(for: changes), "--"] + paths, in: repository)
        return true
    }

    struct Change {
        let file: URL
        let characterDelta: Int
    }

    /// The commit message. Kept separate so it can later be replaced by a generated summary.
    static func message(for changes: [Change]) -> String {
        func describe(_ change: Change) -> String {
            let sign = change.characterDelta < 0 ? "-" : "+"
            return "\(change.file.lastPathComponent) (\(sign)\(abs(change.characterDelta)) chars)"
        }
        if changes.count == 1 {
            return "Edit " + describe(changes[0])
        }
        return "Edit \(changes.count) files\n\n" + changes.map { "- " + describe($0) }.joined(separator: "\n")
    }
}
