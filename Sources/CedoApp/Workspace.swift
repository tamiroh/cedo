import AppKit
import CedoKit
import Foundation

@MainActor
final class Workspace: ObservableObject {
    struct Lint {
        let id = UUID()
        let file: URL
        let text: String
        let diagnostics: [Textlint.Diagnostic]
    }

    private static let saveDelay: TimeInterval = 1
    private static let maxSaveDelay: TimeInterval = 5
    private static let outsideChangeInterval: TimeInterval = 1
    private static let lintDelay: Duration = .milliseconds(500)

    @Published private(set) var root: FileNode?
    @Published private(set) var selectedFile: URL?
    @Published private(set) var document: Document? {
        didSet { documentDidChange(from: oldValue) }
    }
    @Published private(set) var lint: Lint?
    @Published private(set) var configuration: Configuration?
    @Published private(set) var saveFailed = false
    @Published private(set) var shell: ShellSession?
    @Published var ui = UIState.load() {
        didSet { ui.save() }
    }
    @Published private(set) var historyVersion = 0
    /// Shown in place of the editor until a file is selected.
    @Published private(set) var readThroughFolder: URL?

    private var saveTimer: Timer?
    private var unsavedSince: Date?
    private var outsideChangeTimer: Timer?
    private var isResolvingConflict = false
    private var textlint: Textlint?
    private var configurationModificationDate: Date?
    private var lintTask: Task<Void, Never>?
    private var lastLintError: String?
    let log = DebugLog()
    private lazy var autoCommitter = AutoCommitter(log: log)

    var text: String { document?.text ?? "" }
    var errorMessage: String? {
        guard let selectedFile, document == nil else { return nil }
        return "Cannot open \(selectedFile.lastPathComponent) as UTF-8 text."
    }
    var panel: UIState.Panel? { ui.panel }
    var notes: [UIState.Note] { root.flatMap { ui.notes[$0.url.path] } ?? [] }

    init() {
        autoCommitter.onCommit = { [weak self] in self?.historyVersion += 1 }

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
        outsideChangeTimer = Timer.scheduledTimer(withTimeInterval: Self.outsideChangeInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkForOutsideChanges()
                self?.reloadConfigurationIfChanged()
            }
        }
    }

    func prepareToQuit() -> Bool {
        guard saveBeforeLeaving() else { return false }
        autoCommitter.flushAndWait()
        return true
    }

    func toggle(_ panel: UIState.Panel) {
        if self.panel == panel {
            ui.panel = nil
        } else {
            show(panel)
        }
    }

    func show(_ panel: UIState.Panel) {
        if panel == .terminal {
            guard let root else { return }
            if shell == nil {
                startShell(in: root.url)
            }
        }
        ui.panel = panel
    }

    private func startShell(in directory: URL) {
        log.info("Started a shell in \(directory.lastPathComponent)")
        shell = ShellSession(directory: directory) { [weak self] session in
            // Ignore exits from a shell that has already been replaced
            guard let self, self.shell === session else { return }
            self.log.info("The shell exited")
            self.shell = nil
            if self.panel == .terminal {
                self.ui.panel = nil
            }
        }
    }

    func toggleHiddenFiles() {
        ui.showsHiddenFiles.toggle()
        log.info(ui.showsHiddenFiles ? "Showing hidden files" : "Hiding hidden files")
        if let root {
            self.root = FileNode(url: root.url, includesHiddenFiles: ui.showsHiddenFiles)
        }
    }

    func newFile(in directory: URL? = nil) {
        guard let root else { return }
        let folder = directory ?? selectedFile?.deletingLastPathComponent() ?? root.url
        let field = NSTextField(string: "Untitled.md")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        let alert = NSAlert()
        alert.messageText = "New File"
        alert.informativeText = "In \(folder.lastPathComponent)"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains("/") else {
            showAlert("“\(name)” can't be used as a file name.")
            return
        }
        let file = folder.appendingPathComponent(name)
        do {
            try Data().write(to: file, options: .withoutOverwriting)
        } catch {
            showAlert(
                FileManager.default.fileExists(atPath: file.path)
                    ? "\(name) already exists." : "Couldn't create \(name): \(error.localizedDescription)")
            return
        }
        log.info("Created \(name)")
        self.root = FileNode(url: root.url, includesHiddenFiles: ui.showsHiddenFiles)
        select(file)
    }

    func newProject() {
        let panel = NSSavePanel()
        panel.title = "New Project"
        panel.nameFieldLabel = "Project Name:"
        panel.nameFieldStringValue = "Untitled"
        panel.prompt = "Create"
        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let name = folder.lastPathComponent
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        } catch {
            showAlert(
                FileManager.default.fileExists(atPath: folder.path)
                    ? "\(name) already exists." : "Couldn't create \(name): \(error.localizedDescription)")
            return
        }
        do {
            try Git.createRepository(in: folder)
        } catch {
            log.error("Couldn't set up history in \(folder.path): \(error.localizedDescription)")
            showAlert("Created \(name), but couldn't set it up to keep history: \(error.localizedDescription)")
            return
        }
        log.info("Created project \(folder.path)")
        open(folder: folder)
        if root?.url == folder {
            newFile()
        }
    }

    /// Pinning a file that is already pinned brings its note to the front.
    func pinNote(_ file: URL, at origin: CGPoint? = nil) {
        guard !isDirectory(file) else { return }
        editNotes { notes in
            var note = notes.first { $0.path == file.path } ?? UIState.Note(path: file.path)
            if let origin {
                note.frame = CGRect(origin: origin, size: note.frame?.size ?? UIState.Note.defaultSize)
            }
            notes.removeAll { $0.path == file.path }
            notes.append(note)
        }
        ui.showsNotes = true
        log.info("Pinned \(file.lastPathComponent) as a note")
    }

    func moveNote(_ path: String, to frame: CGRect) {
        editNotes { notes in
            notes.removeAll { $0.path == path }
            notes.append(UIState.Note(path: path, frame: frame))
        }
    }

    func unpinNote(_ path: String) {
        editNotes { $0.removeAll { $0.path == path } }
    }

    func toggleNotes() {
        ui.showsNotes.toggle()
    }

    private func editNotes(_ edit: (inout [UIState.Note]) -> Void) {
        guard let root else { return }
        var notes = ui.notes[root.url.path] ?? []
        edit(&notes)
        ui.notes[root.url.path] = notes.isEmpty ? nil : notes
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.runModal()
    }

    func restoreOrPrompt() {
        guard root == nil else { return }
        if let path = ui.folderPath, isDirectory(URL(fileURLWithPath: path)) {
            open(folder: URL(fileURLWithPath: path))
        } else {
            // A modal panel run from onAppear keeps the window from showing, and can open behind other apps
            DispatchQueue.main.async {
                NSApp.activate()
                self.promptForFolder()
            }
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
        readThroughFolder = nil
        log.info("Opened folder \(folder.path)")
        root = FileNode(url: folder, includesHiddenFiles: ui.showsHiddenFiles)
        textlint = Textlint(root: folder)
        if textlint != nil {
            log.info("Found textlint in \(folder.lastPathComponent)")
        }
        configurationModificationDate = nil
        configuration = nil
        reloadConfigurationIfChanged()
        clearEditor()
        shell?.terminate()
        shell = nil
        if panel == .terminal {
            startShell(in: folder)
        }
        ui.folderPath = folder.path

        if let path = ui.filePaths[folder.path], FileManager.default.fileExists(atPath: path),
            !isDirectory(URL(fileURLWithPath: path))
        {
            load(URL(fileURLWithPath: path))
        }
    }

    func readThrough(_ folder: URL) {
        save()
        readThroughFolder = folder
        log.info("Reading through \(folder.lastPathComponent)")
    }

    func select(_ url: URL?) {
        if url != nil {
            readThroughFolder = nil
        }
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
        // Waits for a pause in typing, but not so long that a crash loses much
        let unsavedSince = self.unsavedSince ?? .now
        self.unsavedSince = unsavedSince
        let delay = min(Self.saveDelay, max(0, Self.maxSaveDelay + unsavedSince.timeIntervalSinceNow))
        saveTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    func save() {
        saveTimer?.invalidate()
        saveTimer = nil
        unsavedSince = nil
        guard !isResolvingConflict else { return }
        write()
    }

    private func write(overwritingOutsideChanges: Bool = false) {
        guard let url = document?.url else { return }
        do {
            switch try document?.save(overwritingOutsideChanges: overwritingOutsideChanges) {
            case .saved:
                log.info("Saved \(url.lastPathComponent)")
                saveFailed = false
                autoCommitter.fileSaved(url)
            case .conflict(let onDisk):
                resolveConflict(in: url, onDisk: onDisk)
            case .unreadable:
                if !saveFailed {
                    log.error("Stopped saving \(url.lastPathComponent): it was deleted or is no longer UTF-8 text")
                }
                saveFailed = true
            case .unchanged, nil:
                break
            }
        } catch {
            saveFailed = true
            log.error("Couldn't save \(url.lastPathComponent): \(error.localizedDescription)")
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
            log.info("Reloaded \(checked.url.lastPathComponent) after it changed outside Cedo")
            saveFailed = false
        case .conflict(let onDisk):
            resolveConflict(in: checked.url, onDisk: onDisk)
        case .unchanged:
            break
        }
    }

    private func resolveConflict(in url: URL, onDisk: String) {
        isResolvingConflict = true
        defer { isResolvingConflict = false }
        log.info("\(url.lastPathComponent) changed outside Cedo while being edited")

        let alert = NSAlert()
        alert.messageText = "\(url.lastPathComponent) was changed outside Cedo."
        alert.informativeText = "You were editing it at the same time. Which version do you want to keep?"
        alert.addButton(withTitle: "Keep Mine")
        alert.addButton(withTitle: "Use the Other Version")
        if alert.runModal() == .alertFirstButtonReturn {
            autoCommitter.fileSaved(url)
            autoCommitter.flushAndWait()
            log.info("Kept the edits in Cedo")
            write(overwritingOutsideChanges: true)
        } else {
            log.info("Took the version changed outside Cedo")
            document?.adopt(onDisk)
            saveFailed = false
        }
    }

    private func saveBeforeLeaving() -> Bool {
        save()
        guard let document, document.isDirty else { return true }
        let alert = NSAlert()
        alert.messageText = "Couldn't save \(document.url.lastPathComponent)."
        alert.informativeText = "If you continue, your latest changes will be lost."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Discard Changes")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        log.info("Discarded unsaved edits to \(document.url.lastPathComponent)")
        return true
    }

    private func load(_ url: URL) {
        clearEditor()
        selectedFile = url
        if let root {
            ui.filePaths[root.url.path] = url.path
        }
        document = Document(url: url)
        if document == nil {
            log.error("Couldn't open \(url.lastPathComponent) as UTF-8 text")
        }
    }

    private func clearEditor() {
        saveTimer?.invalidate()
        saveTimer = nil
        unsavedSince = nil
        selectedFile = nil
        document = nil
        saveFailed = false
    }

    private func documentDidChange(from old: Document?) {
        let isNewFile = document?.url != old?.url
        guard isNewFile || document?.text != old?.text else { return }
        lintTask?.cancel()
        if isNewFile {
            lint = nil
            runLint()
        } else {
            runLint(after: Self.lintDelay)
        }
    }

    private func runLint(after delay: Duration = .zero) {
        guard let textlint, let document else { return }
        let text = document.text
        let file = document.url
        lintTask = Task {
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            do {
                let diagnostics = try await textlint.lint(text, of: file)
                lint = Lint(file: file, text: text, diagnostics: diagnostics)
                lastLintError = nil
            } catch {
                guard !Task.isCancelled else { return }
                // The same failure would otherwise be logged after every pause in typing
                let message = error.localizedDescription
                if message != lastLintError {
                    log.error("textlint failed: \(message)")
                }
                lastLintError = message
            }
        }
    }

    private func reloadConfigurationIfChanged() {
        guard let root else { return }
        let url = Configuration.url(in: root.url)
        let date = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        guard date != configurationModificationDate else { return }
        configurationModificationDate = date
        do {
            configuration = try Configuration(root: root.url)
            if configuration != nil {
                log.info("Loaded \(Configuration.fileName)")
            }
        } catch {
            configuration = nil
            log.error(error.localizedDescription)
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
