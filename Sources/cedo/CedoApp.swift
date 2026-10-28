import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { workspace.promptForFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { workspace.save() }
                    .keyboardShortcut("s")
                    .disabled(workspace.selectedFile == nil)
            }
        }
    }
}
