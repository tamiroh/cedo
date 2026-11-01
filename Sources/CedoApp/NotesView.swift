import CedoKit
import SwiftUI

/// Files pinned over the editor to read while writing, such as an outline or a glossary.
struct NotesView: View {
    @EnvironmentObject private var workspace: Workspace

    var body: some View {
        GeometryReader { geometry in
            ForEach(Array(workspace.notes.enumerated()), id: \.element.path) { index, note in
                NoteView(note: note, frame: frame(of: note, at: index, in: geometry.size))
            }
        }
    }

    /// Kept inside the editor area, so a note never ends up out of reach after the window shrinks.
    private func frame(of note: UIState.Note, at index: Int, in bounds: CGSize) -> CGRect {
        let size = note.frame?.size ?? UIState.Note.defaultSize
        let origin =
            note.frame?.origin
            ?? CGPoint(x: bounds.width - size.width - 24, y: 60 + CGFloat(index) * 28)
        return CGRect(
            x: min(max(origin.x, 0), max(bounds.width - 80, 0)),
            y: min(max(origin.y, 0), max(bounds.height - 40, 0)),
            width: size.width, height: size.height
        )
    }
}

private struct NoteView: View {
    private static let minimumSize = CGSize(width: 160, height: 100)
    private static let resizeCursor: NSCursor = {
        if #available(macOS 15, *) {
            return .frameResize(position: .bottomRight, directions: .all)
        }
        return .crosshair
    }()

    @EnvironmentObject private var workspace: Workspace
    let note: UIState.Note
    let frame: CGRect
    @State private var moved: CGSize = .zero
    @State private var resized: CGSize = .zero
    @State private var savedText: String?
    @State private var modificationDate: Date?

    private var file: URL { URL(fileURLWithPath: note.path) }

    private var size: CGSize {
        CGSize(
            width: max(frame.width + resized.width, Self.minimumSize.width),
            height: max(frame.height + resized.height, Self.minimumSize.height)
        )
    }

    /// The open file is shown as it is being written, ahead of what is saved.
    private var text: String? {
        if workspace.selectedFile == file, let document = workspace.document {
            return document.text
        }
        return savedText
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView {
                Group {
                    if let text {
                        Text(highlighted(text, by: workspace.configuration))
                            .textSelection(.enabled)
                    } else {
                        Text("Can't read \(file.lastPathComponent).")
                            .foregroundStyle(Theme.muted)
                    }
                }
                .font(.system(size: 12))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        .overlay(alignment: .bottomTrailing) { resizeHandle }
        .offset(x: frame.minX + moved.width, y: frame.minY + moved.height)
        .task(id: note.path) {
            while !Task.isCancelled {
                reloadIfChanged()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(file.lastPathComponent)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button {
                workspace.unpinNote(note.path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .cursor(.openHand)
        // Like a window's title bar: drag to move, double-click to open the file in the editor
        .onTapGesture(count: 2) { workspace.select(file) }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged {
                    moved = $0.translation
                    NSCursor.closedHand.set()
                }
                .onEnded { _ in
                    commit(origin: CGPoint(x: frame.minX + moved.width, y: frame.minY + moved.height))
                    moved = .zero
                    NSCursor.openHand.set()
                }
        )
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 8))
            .foregroundStyle(Theme.muted)
            .rotationEffect(.degrees(90))
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .cursor(Self.resizeCursor)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { resized = $0.translation }
                    .onEnded { _ in
                        commit(origin: frame.origin)
                        resized = .zero
                    }
            )
    }

    private func commit(origin: CGPoint) {
        workspace.moveNote(note.path, to: CGRect(origin: origin, size: size))
    }

    private func reloadIfChanged() {
        // A fresh URL each time, as a URL caches the resource values it has read
        let file = URL(fileURLWithPath: note.path)
        let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard savedText == nil || date != modificationDate else { return }
        modificationDate = date
        savedText = (try? Data(contentsOf: file)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

extension View {
    /// Set on every move, as the editor underneath would otherwise put its own cursor back.
    fileprivate func cursor(_ cursor: NSCursor) -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active: cursor.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}

/// The text with the highlights of `.cedo.json`, for views that show text without editing it.
func highlighted(_ text: String, by configuration: Configuration?) -> AttributedString {
    var result = AttributedString(text)
    guard let configuration else { return result }
    for match in configuration.highlightMatches(in: text) {
        guard let range = Range(match.range, in: result) else { continue }
        let highlight = configuration.highlights[match.highlight]
        if let color = highlight.color {
            result[range].foregroundColor = Color(hex: color)
        }
        if let background = highlight.background {
            result[range].backgroundColor = Color(hex: background)
        }
        if highlight.color == nil, highlight.background == nil {
            result[range].backgroundColor = Theme.selection
        }
    }
    return result
}
