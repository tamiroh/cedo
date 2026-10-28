import AppKit
import Foundation

@MainActor
final class Workspace: ObservableObject {
    private static let lastFolderKey = "lastFolderPath"

    @Published private(set) var root: FileNode?
    @Published var selectedFile: URL?
    @Published var text = ""
    @Published private(set) var isDirty = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shell: ShellSession?
    @Published private(set) var isTerminalVisible = false

    private var savedText = ""

    func toggleTerminal() {
        guard let root else { return }
        isTerminalVisible.toggle()
        if isTerminalVisible && shell == nil {
            startShell(in: root.url)
        }
    }

    private func startShell(in directory: URL) {
        shell = ShellSession(directory: directory) { [weak self] session in
            // Ignore exits from a shell that has already been replaced
            guard let self, self.shell === session else { return }
            self.shell = nil
            self.isTerminalVisible = false
        }
    }

    func restoreOrPrompt() {
        guard root == nil else { return }
        if let path = UserDefaults.standard.string(forKey: Self.lastFolderKey),
           isDirectory(URL(fileURLWithPath: path)) {
            open(folder: URL(fileURLWithPath: path))
        } else {
            promptForFolder()
        }
    }

    func promptForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(folder: url)
    }

    func open(folder: URL) {
        guard confirmDiscardIfNeeded() else { return }
        root = FileNode(url: folder)
        clearEditor()
        // The shell belongs to the old folder, so start a fresh one
        shell?.terminate()
        shell = nil
        if isTerminalVisible {
            startShell(in: folder)
        }
        UserDefaults.standard.set(folder.path, forKey: Self.lastFolderKey)
    }

    func select(_ url: URL?) {
        guard url != selectedFile else { return }
        guard let url, !isDirectory(url) else { return }
        guard confirmDiscardIfNeeded() else { return }
        load(url)
    }

    func textDidChange(_ newText: String) {
        text = newText
        isDirty = newText != savedText
    }

    func save() {
        guard let url = selectedFile else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            savedText = text
            isDirty = false
        } catch {
            showError("Failed to save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func load(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            selectedFile = url
            text = content
            savedText = content
            isDirty = false
            errorMessage = nil
        } catch {
            clearEditor()
            selectedFile = url
            errorMessage = "Cannot open \(url.lastPathComponent) as UTF-8 text."
        }
    }

    private func clearEditor() {
        selectedFile = nil
        text = ""
        savedText = ""
        isDirty = false
        errorMessage = nil
    }

    /// Asks to save, discard, or cancel when there are unsaved changes. Returns true if it is OK to proceed.
    private func confirmDiscardIfNeeded() -> Bool {
        guard isDirty, let url = selectedFile else { return true }
        let alert = NSAlert()
        alert.messageText = "Save changes to \(url.lastPathComponent)?"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
