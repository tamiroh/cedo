import Foundation

struct Commit: Identifiable, Hashable {
    let hash: String
    let shortHash: String
    let author: String
    let date: String
    let subject: String
    /// The file's path at this commit, relative to the repository root.
    let path: String

    var id: String { hash }
}

enum Git {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Commits that touched the file, newest first, following renames.
    static func history(of file: URL) async throws -> [Commit] {
        let output = try await run(
            ["log", "--follow", "--no-color", "--name-only",
             "--format=%x1e%H%x1f%h%x1f%an%x1f%ar%x1f%s",
             "--", file.lastPathComponent],
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
    static func diff(of commit: Commit, near file: URL) async throws -> String {
        try await run(
            ["show", "--no-color", "--format=", commit.hash, "--", ":(top)" + commit.path],
            in: file.deletingLastPathComponent()
        )
    }

    private static func run(_ arguments: [String], in directory: URL) async throws -> String {
        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory.path] + arguments
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
        }.value
    }
}
