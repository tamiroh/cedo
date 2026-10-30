import AppKit

/// Draws wavy underlines below the text that textlint reported.
final class LintLayoutManager: NSLayoutManager {
    struct Mark {
        var range: NSRange
        let message: String
        let isError: Bool
    }

    /// Redrawing after a change is up to the caller.
    var marks: [Mark] = []

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        for mark in marks {
            let glyphs = NSIntersectionRange(glyphRange(forCharacterRange: mark.range, actualCharacterRange: nil), glyphsToShow)
            guard glyphs.length > 0 else { continue }
            NSColor(mark.isError ? Theme.danger : Theme.warning).setStroke()
            enumerateLineFragments(forGlyphRange: glyphs) { lineRect, _, container, lineGlyphs, _ in
                let range = NSIntersectionRange(lineGlyphs, glyphs)
                let bounds = self.boundingRect(forGlyphRange: range, in: container)
                let baseline = lineRect.minY + self.location(forGlyphAt: range.location).y
                Self.wave(from: bounds.minX + origin.x, to: bounds.maxX + origin.x, y: baseline + origin.y + 3).stroke()
            }
        }
    }

    private static func wave(from start: CGFloat, to end: CGFloat, y: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.lineWidth = 1
        path.move(to: NSPoint(x: start, y: y))
        var x = start
        var isUp = true
        while x < end {
            x = min(x + 2, end)
            path.line(to: NSPoint(x: x, y: y + (isUp ? -1.5 : 1.5)))
            isUp.toggle()
        }
        return path
    }
}
