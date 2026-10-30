import Foundation

public struct Commit: Identifiable, Hashable {
    public let hash: String
    public let shortHash: String
    public let author: String
    public let date: String
    public let subject: String
    /// The file's path at this commit, relative to the repository root.
    public let path: String

    public var id: String { hash }
}

public enum Git {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Commits that touched the file, newest first, following renames.
    public static func history(of file: URL) async throws -> [Commit] {
        let output = try await run(
            [
                "log", "--follow", "--no-color", "--name-only",
                "--format=%x1e%H%x1f%h%x1f%an%x1f%ar%x1f%s",
                "--", file.lastPathComponent,
            ],
            in: file.deletingLastPathComponent()
        )
        return output.split(separator: "\u{1e}").compactMap { record in
            let lines = record.split(separator: "\n")
            guard let header = lines.first, let path = lines.dropFirst().first else { return nil }
            let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 5 else { return nil }
            return Commit(
                hash: fields[0], shortHash: fields[1], author: fields[2],
                date: fields[3], subject: fields[4], path: String(path)
            )
        }
    }

    /// The changes the commit made to the file.
    public static func diff(of commit: Commit, near file: URL) async throws -> String {
        try await run(
            ["show", "--no-color", "--format=", commit.hash, "--", ":(top)" + commit.path],
            in: file.deletingLastPathComponent()
        )
    }

    /// The root of the repository that contains the file.
    static func topLevel(of file: URL) throws -> URL {
        let path = try runSync(["rev-parse", "--show-toplevel"], in: file.deletingLastPathComponent())
        return URL(fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The file's content at HEAD, or nil if it is not committed yet.
    static func headVersion(of file: URL) -> String? {
        try? runSync(["show", "HEAD:./" + file.lastPathComponent], in: file.deletingLastPathComponent())
    }

    private static func run(_ arguments: [String], in directory: URL) async throws -> String {
        try await Task.detached { try runSync(arguments, in: directory) }.value
    }

    /// Runs git and returns its output. Blocks until git exits.
    @discardableResult
    static func runSync(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
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

        guard process.terminationStatus == 0 else {
            let message = String(decoding: error, as: UTF8.self)
            if message.contains("not a git repository") {
                throw Failure(message: "This file is not in a Git repository.")
            }
            throw Failure(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: output, as: UTF8.self)
    }
}
