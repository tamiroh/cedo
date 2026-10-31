import Foundation

public struct Textlint: Sendable {
    public struct Diagnostic: Equatable, Sendable {
        /// In UTF-16 code units, as in `NSString`.
        public let range: NSRange
        public let message: String
        public let ruleID: String
        public let isError: Bool
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let configNames = [
        ".textlintrc", ".textlintrc.json", ".textlintrc.yml", ".textlintrc.yaml", ".textlintrc.js", ".textlintrc.cjs",
    ]

    public let root: URL
    private let executable: URL

    public init?(root: URL) {
        let fileManager = FileManager.default
        let executable = root.appendingPathComponent("node_modules/.bin/textlint")
        guard
            Self.configNames.contains(where: { fileManager.fileExists(atPath: root.appendingPathComponent($0).path) }),
            fileManager.isExecutableFile(atPath: executable.path)
        else { return nil }
        self.root = root
        self.executable = executable
    }

    public func lint(_ text: String, of file: URL) async throws -> [Diagnostic] {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["--format", "json", "--stdin", "--stdin-filename", file.path]
        process.currentDirectoryURL = root
        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global().async {
                    continuation.resume(with: Result { try Self.run(process, input: text) })
                }
            }
        } onCancel: {
            // terminate() throws if the process has not been launched yet
            if process.isRunning {
                process.terminate()
            }
        }
        try Task.checkCancellation()
        do {
            return try Self.parse(output)
        } catch {
            let message = String(decoding: output, as: UTF8.self)
            // A file type that no textlint plugin reads, such as source code
            if message.contains("Not found available plugin") {
                return []
            }
            throw Failure(message: message.split(separator: "\n").first.map(String.init) ?? "textlint printed nothing.")
        }
    }

    private static func run(_ process: Process, input: String) throws -> Data {
        process.environment = LoginEnvironment.variables
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()

        // Write and read at the same time, so neither side waits on a full pipe
        let group = DispatchGroup()
        let error = Handoff(Data())
        DispatchQueue.global().async(group: group) {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        DispatchQueue.global().async(group: group) {
            error.value = stderr.fileHandleForReading.readDataToEndOfFile()
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        // textlint exits with 1 when it finds problems, which is not a failure
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else {
            let message = String(decoding: error.value.isEmpty ? output : error.value, as: UTF8.self)
            throw Failure(message: message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output
    }

    static func parse(_ output: Data) throws -> [Diagnostic] {
        struct Result: Decodable {
            let messages: [Message]
        }
        struct Message: Decodable {
            let ruleId: String?
            let message: String
            let index: Int
            let range: [Int]?
            let severity: Int
        }

        return try JSONDecoder().decode([Result].self, from: output).flatMap(\.messages).map { message in
            let start = message.range?.first ?? message.index
            let end = message.range?.last ?? start
            return Diagnostic(
                // Empty ranges would draw nothing, so mark at least one character
                range: NSRange(location: start, length: max(end - start, 1)),
                message: message.message.trimmingCharacters(in: .whitespacesAndNewlines),
                ruleID: message.ruleId ?? "",
                isError: message.severity >= 2
            )
        }
    }
}
