import AppKit
import SwiftUI

/// Hosts the session's terminal view, which is reused across shows so the shell keeps running.
struct TerminalPanel: NSViewRepresentable {
    let session: ShellSession

    func makeNSView(context: Context) -> NSView {
        let view = session.view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
