import Foundation

/// Apps opened from the Finder get a minimal PATH, so tools installed with Homebrew, asdf and the like
/// can only be found through the shell's own configuration.
public enum LoginEnvironment {
    public static let variables: [String: String] = load() ?? ProcessInfo.processInfo.environment

    private static let marker = "__CEDO_ENVIRONMENT__"

    private static func load() -> [String: String]? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        // Interactive, so that settings kept in .zshrc and the like are included.
        // The markers separate the variables from anything the startup files print.
        process.arguments = ["-l", "-i", "-c", "printf '\(marker)'; /usr/bin/env -0; printf '\(marker)'"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let timeout = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: timeout)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()

        let parts = String(decoding: data, as: UTF8.self).components(separatedBy: marker)
        guard process.terminationStatus == 0, parts.count == 3 else { return nil }
        var variables: [String: String] = [:]
        for entry in parts[1].split(separator: "\0") {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            variables[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        return variables
    }
}
