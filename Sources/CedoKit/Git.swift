import Foundation

public struct Commit: Identifiable, Hashable, Sendable {
    public let hash: String
    public let date: Date
    public let subject: String
    public let added: Int
    public let removed: Int
    public let path: String

    public var id: String { hash }
}

public enum Git {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    public static func history(of file: URL) async throws -> [Commit] {
        let directory = file.deletingLastPathComponent()
        guard try await !run(["rev-parse", "--revs-only", "HEAD"], in: directory).isEmpty else { return [] }
        let output = try await run(
            [
                "log", "--follow", "--no-color", "--patch", "--unified=0",
                "--format=%x1e%H%x1f%at%x1f%s",
                "--", ":(literal)" + file.lastPathComponent,
            ],
            in: file.deletingLastPathComponent()
        )
        return output.split(separator: "\u{1e}").compactMap { record in
            let lines = record.split(separator: "\n")
            guard let header = lines.first, let path = path(inPatch: lines.dropFirst()) else { return nil }
            let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 3, let seconds = TimeInterval(fields[1]) else { return nil }
            let size = size(of: lines.dropFirst().joined(separator: "\n"))
            return Commit(
                hash: fields[0], date: Date(timeIntervalSince1970: seconds), subject: fields[2],
                added: size.added, removed: size.removed, path: path
            )
        }
    }

    static func path(inPatch lines: some Sequence<Substring>) -> String? {
        var path: String?
        for line in lines {
            if line.hasPrefix("+++ b/") {
                return String(line.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\t"))
            }
            if line.hasPrefix("rename to ") {
                path = String(line.dropFirst(10))
            } else if line.hasPrefix("--- a/"), path == nil {
                path = String(line.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\t"))
            } else if line.hasPrefix("@@") {
                break
            }
        }
        return path
    }

    /// Counts only the changed part of a rewritten line, so fixing one character in a paragraph counts as one.
    public static func size(of patch: String) -> (added: Int, removed: Int) {
        Diff.edits(in: patch).reduce(into: (added: 0, removed: 0)) { size, edit in
            switch edit {
            case .rewritten(let old, let new):
                let (removed, added) = Diff.changedTexts(old, new)
                size.removed += removed.count
                size.added += added.count
            case .removed(let text): size.removed += text.count
            case .added(let text): size.added += text.count
            }
        }
    }

    public static func currentDiff(of file: URL, text: String) async throws -> String {
        try await Task.detached {
            var previous = headVersion(of: file) ?? ""
            if previous.unicodeScalars.first == "\u{FEFF}" {
                previous.unicodeScalars.removeFirst()
            }
            guard !Document.same(previous, text) else { return "" }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            try Data(previous.utf8).write(to: directory.appendingPathComponent("previous"))
            try Data(text.utf8).write(to: directory.appendingPathComponent("current"))
            return try runSync(
                ["diff", "--no-index", "--no-color", "--no-ext-diff", "--", "previous", "current"],
                in: directory, successStatuses: [0, 1])
        }.value
    }

    public static func diff(of commit: Commit, near file: URL) async throws -> String {
        try await run(
            ["show", "--no-color", "--format=", commit.hash, "--", ":(top,literal)" + commit.path],
            in: file.deletingLastPathComponent()
        )
    }

    public static func createRepository(in folder: URL) throws {
        try runSync(["init", "--quiet"], in: folder)
    }

    static func topLevel(of file: URL) throws -> URL {
        let path = try runSync(["rev-parse", "--show-toplevel"], in: file.deletingLastPathComponent())
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func headVersion(of file: URL) -> String? {
        try? runSync(["show", "HEAD:./" + file.lastPathComponent], in: file.deletingLastPathComponent())
    }

    private static func run(_ arguments: [String], in directory: URL) async throws -> String {
        try await Task.detached { try runSync(arguments, in: directory) }.value
    }

    @discardableResult
    static func runSync(
        _ arguments: [String], in directory: URL, environment: [String: String] = [:], successStatuses: Set<Int32> = [0]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        // Without core.quotePath=false, git escapes non-ASCII paths such as Japanese file names
        process.arguments = ["-C", directory.path, "-c", "core.quotePath=false"] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        // Read before waiting so a large output cannot fill the pipe and block git
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let error = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard successStatuses.contains(process.terminationStatus) else {
            let message = String(lossyUTF8: error)
            if message.contains("not a git repository") {
                throw Failure(message: "This file is not in a Git repository.")
            }
            throw Failure(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(lossyUTF8: output)
    }
}
