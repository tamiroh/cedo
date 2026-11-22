import AppKit
import CedoUI
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor private(set) lazy var workspace = Workspace()

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
        MainActor.assumeIsolated { workspace.prepareToQuit() } ? .terminateNow : .terminateCancel
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct CedoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        EditorWindow(workspace: appDelegate.workspace)
    }
}
