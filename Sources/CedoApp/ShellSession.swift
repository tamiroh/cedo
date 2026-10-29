import AppKit
import SwiftTerm

/// Owns a terminal view and the login shell running in it, so the session
/// survives the terminal panel being hidden and shown again.
final class ShellSession: NSObject, LocalProcessTerminalViewDelegate {
    let view: LocalProcessTerminalView
    private let onExit: (ShellSession) -> Void

    init(directory: URL, onExit: @escaping (ShellSession) -> Void) {
        self.view = LocalProcessTerminalView(frame: .zero)
        self.onExit = onExit
        super.init()

        view.processDelegate = self
        view.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        view.nativeForegroundColor = NSColor(Theme.text)
        view.nativeBackgroundColor = NSColor(Theme.inset)
        view.caretColor = NSColor(Theme.text)
        view.selectedTextBackgroundColor = NSColor(Theme.selection)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        view.startProcess(
            executable: shell,
            environment: Self.environment(),
            // A leading "-" in argv[0] makes the shell start as a login shell
            execName: "-" + (shell as NSString).lastPathComponent,
            currentDirectory: directory.path
        )
    }

    func terminate() {
        view.terminate()
    }

    /// The app's own environment, with the terminal-specific variables SwiftTerm recommends.
    private static func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        for entry in Terminal.getEnvironmentVariables(termName: "xterm-256color") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { env[String(parts[0])] = String(parts[1]) }
        }
        return env.map { "\($0.key)=\($0.value)" }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { self.onExit(self) }
    }
}
