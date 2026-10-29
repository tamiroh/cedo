import AppKit
import Foundation

@MainActor
final class Workspace: ObservableObject {
    private static let lastFolderKey = "lastFolderPath"
    private static let saveDelay: TimeInterval = 1
    private static let outsideChangeInterval: TimeInterval = 1

    @Published private(set) var root: FileNode?
    @Published var selectedFile: URL?
    @Published var text = ""
    @Published private(set) var saveFailed = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shell: ShellSession?
    @Published private(set) var isTerminalVisible = false
    /// Bumped after each auto-commit so the history view can reload.
    @Published private(set) var historyVersion = 0

    /// The file's content as cedo last read or wrote it, used to spot both unsaved edits and outside changes.
    private var savedText = ""
    private var savedModificationDate: Date?
    private var saveTimer: Timer?
    private var outsideChangeTimer: Timer?
    private var isResolvingConflict = false
    private let autoCommitter = AutoCommitter()

    private var isDirty: Bool { text != savedText }

    init() {
        autoCommitter.onCommit = { [weak self] in self?.historyVersion += 1 }

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.save()
                // Make sure the last edits are committed before the app exits
                self?.autoCommitter.flushAndWait()
            }
        }
        outsideChangeTimer = Timer.scheduledTimer(withTimeInterval: Self.outsideChangeInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForOutsideChanges() }
        }
    }

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
        guard saveBeforeLeaving() else { return }
        autoCommitter.flush()
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
        guard saveBeforeLeaving() else { return }
        autoCommitter.flush()
        load(url)
    }

    func textDidChange(_ newText: String) {
        text = newText
        autoCommitter.textChanged()
        saveTimer?.invalidate()
        saveTimer = Timer.scheduledTimer(withTimeInterval: Self.saveDelay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    /// Writes pending edits to disk, unless the file was changed outside cedo in the meantime.
    func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        guard let url = selectedFile, errorMessage == nil, isDirty, !isResolvingConflict else { return }
        if let onDisk = try? String(contentsOf: url, encoding: .utf8), onDisk != savedText {
            resolveConflict(in: url, onDisk: onDisk)
        } else {
            write(text, to: url)
        }
    }

    private func write(_ content: String, to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            savedText = content
            savedModificationDate = modificationDate(of: url)
            saveFailed = false
            autoCommitter.fileSaved(url)
        } catch {
            saveFailed = true
            NSLog("cedo: failed to save %@: %@", url.path, error.localizedDescription)
        }
    }

    /// Picks up changes made to the open file by something else, such as a command in the terminal.
    private func checkForOutsideChanges() {
        guard let url = selectedFile, errorMessage == nil, !isResolvingConflict else { return }
        let date = modificationDate(of: url)
        guard date != savedModificationDate,
              let onDisk = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard onDisk != savedText else {
            savedModificationDate = date
            return
        }
        if isDirty {
            resolveConflict(in: url, onDisk: onDisk)
        } else {
            adopt(onDisk, from: url)
        }
    }

    /// Both cedo and something else changed the file; asks which version to keep.
    private func resolveConflict(in url: URL, onDisk: String) {
        isResolvingConflict = true
        defer { isResolvingConflict = false }

        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) was changed outside cedo."
        alert.informativeText = "You were editing it at the same time. Which version do you want to keep?"
        alert.addButton(withTitle: "Keep Mine")
        alert.addButton(withTitle: "Use the Other Version")
        if alert.runModal() == .alertFirstButtonReturn {
            // Record the other version in the history before replacing it
            autoCommitter.fileSaved(url)
            autoCommitter.flushAndWait()
            write(text, to: url)
        } else {
            adopt(onDisk, from: url)
        }
    }

    private func adopt(_ content: String, from url: URL) {
        text = content
        savedText = content
        savedModificationDate = modificationDate(of: url)
        saveFailed = false
    }

    /// Saves before leaving the current file. Returns false if saving failed and the user chose to stay.
    private func saveBeforeLeaving() -> Bool {
        save()
        guard isDirty, let url = selectedFile else { return true }
        let alert = NSAlert()
        alert.messageText = "Couldn't save \(url.lastPathComponent)."
        alert.informativeText = "If you continue, your latest changes will be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func load(_ url: URL) {
        clearEditor()
        selectedFile = url
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            adopt(content, from: url)
        } else {
            errorMessage = "Cannot open \(url.lastPathComponent) as UTF-8 text."
        }
    }

    private func clearEditor() {
        saveTimer?.invalidate()
        saveTimer = nil
        selectedFile = nil
        text = ""
        savedText = ""
        savedModificationDate = nil
        saveFailed = false
        errorMessage = nil
    }

    private func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
