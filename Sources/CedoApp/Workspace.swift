import AppKit
import CedoKit
import Foundation

@MainActor
final class Workspace: ObservableObject {
    private static let lastFolderKey = "lastFolderPath"
    private static let saveDelay: TimeInterval = 1
    private static let outsideChangeInterval: TimeInterval = 1

    @Published private(set) var root: FileNode?
    @Published private(set) var selectedFile: URL?
    @Published private(set) var document: Document?
    @Published private(set) var saveFailed = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var shell: ShellSession?
    @Published private(set) var isTerminalVisible = false
    /// Bumped after each auto-commit so the history view can reload.
    @Published private(set) var historyVersion = 0

    private var saveTimer: Timer?
    private var outsideChangeTimer: Timer?
    private var isResolvingConflict = false
    private let autoCommitter = AutoCommitter()

    var text: String { document?.text ?? "" }

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
        document?.text = newText
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
        guard !isResolvingConflict else { return }
        write()
    }

    private func write(overwritingOutsideChanges: Bool = false) {
        guard let url = document?.url else { return }
        do {
            switch try document?.save(overwritingOutsideChanges: overwritingOutsideChanges) {
            case .saved:
                saveFailed = false
                autoCommitter.fileSaved(url)
            case .conflict(let onDisk):
                resolveConflict(in: url, onDisk: onDisk)
            case .unchanged, nil:
                break
            }
        } catch {
            saveFailed = true
            NSLog("cedo: failed to save %@: %@", url.path, error.localizedDescription)
        }
    }

    private func checkForOutsideChanges() {
        guard var checked = document, !isResolvingConflict else { return }
        let change = checked.checkForOutsideChanges()
        // Assigning back on every poll would redraw the views every second
        if checked != document {
            document = checked
        }
        switch change {
        case .reloaded:
            saveFailed = false
        case .conflict(let onDisk):
            resolveConflict(in: checked.url, onDisk: onDisk)
        case .unchanged:
            break
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
            write(overwritingOutsideChanges: true)
        } else {
            document?.adopt(onDisk)
            saveFailed = false
        }
    }

    /// Saves before leaving the current file. Returns false if saving failed and the user chose to stay.
    private func saveBeforeLeaving() -> Bool {
        save()
        guard let document, document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Couldn't save \(document.url.lastPathComponent)."
        alert.informativeText = "If you continue, your latest changes will be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func load(_ url: URL) {
        clearEditor()
        selectedFile = url
        document = Document(url: url)
        if document == nil {
            errorMessage = "Cannot open \(url.lastPathComponent) as UTF-8 text."
        }
    }

    private func clearEditor() {
        saveTimer?.invalidate()
        saveTimer = nil
        selectedFile = nil
        document = nil
        saveFailed = false
        errorMessage = nil
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
