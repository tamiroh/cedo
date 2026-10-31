import AppKit
import SwiftUI

struct TerminalPanel: NSViewRepresentable {
    let session: ShellSession

    func makeNSView(context: Context) -> NSView {
        let view = session.view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
