import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var workspace: Workspace?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // The UI is dark-only, so dialogs and scrollers should match
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Lint messages show on hover, so wait about as long as VS Code instead of the system's second or so
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 300])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Behave as a regular foreground app even when launched via `swift run`
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { workspace?.prepareToQuit() ?? true } ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CedoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var workspace = Workspace()

    var body: some Scene {
        Window("Cedo", id: "main") {
            ContentView()
                .environmentObject(workspace)
                .onAppear {
                    appDelegate.workspace = workspace
                    workspace.restoreOrPrompt()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File…") { workspace.newFile() }
                    .keyboardShortcut("n")
                    .disabled(workspace.root == nil)
                Button("New Project…") { workspace.newProject() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Open Folder…") { workspace.promptForFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { workspace.save() }
                    .keyboardShortcut("s")
                    .disabled(workspace.selectedFile == nil)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Menu("Find") {
                    findButton("Find…", .showFindInterface, "f")
                    findButton("Find and Replace…", .showReplaceInterface, "f", modifiers: [.command, .option])
                    findButton("Find Next", .nextMatch, "g")
                    findButton("Find Previous", .previousMatch, "g", modifiers: [.command, .shift])
                    findButton("Use Selection for Find", .setSearchString, "e")
                }
            }
            CommandGroup(before: .toolbar) {
                Button(workspace.panel == .terminal ? "Hide Terminal" : "Show Terminal") {
                    workspace.toggle(.terminal)
                }
                .keyboardShortcut("`", modifiers: .control)
                .disabled(workspace.root == nil)
                Button(workspace.panel == .log ? "Hide Debug Log" : "Show Debug Log") {
                    workspace.toggle(.log)
                }
                .keyboardShortcut("l", modifiers: [.option, .command])
                Button(workspace.ui.showsNotes ? "Hide Notes" : "Show Notes") { workspace.toggleNotes() }
                    .keyboardShortcut("n", modifiers: [.option, .command])
                    .disabled(workspace.root == nil)
            }
        }
    }

    private func findButton(
        _ title: String, _ action: NSTextFinder.Action, _ key: KeyEquivalent, modifiers: EventModifiers = .command
    ) -> some View {
        Button(title) {
            // The text view reads which action to take from the sender's tag
            let sender = NSMenuItem()
            sender.tag = action.rawValue
            NSApp.sendAction(#selector(NSResponder.performTextFinderAction(_:)), to: nil, from: sender)
        }
        .keyboardShortcut(key, modifiers: modifiers)
    }
}
