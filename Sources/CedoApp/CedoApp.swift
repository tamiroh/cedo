import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // The UI is dark-only, so dialogs and scrollers should match
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Behave as a regular foreground app even when launched via `swift run`
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
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
        Window("cedo", id: "main") {
            ContentView()
                .environmentObject(workspace)
                .onAppear { workspace.restoreOrPrompt() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File…") { workspace.newFile() }
                    .keyboardShortcut("n")
                    .disabled(workspace.root == nil)
                Button("Open Folder…") { workspace.promptForFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { workspace.save() }
                    .keyboardShortcut("s")
                    .disabled(workspace.selectedFile == nil)
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
            }
        }
    }
}
