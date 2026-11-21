import Foundation

extension Workspace {
    var notes: [UIState.Note] { root.flatMap { ui.notes[$0.url.path] } ?? [] }

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
}
