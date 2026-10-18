import AppKit

/// The monochrome Semono mark used by the menu bar in icon-only mode.
///
/// It is a template-style glyph (axis plus the chart line from the app icon),
/// not a scaled app icon: menu bar icons are drawn in the label colour and
/// share the optical weight of the system symbols around them.
enum SemonoMark {
    /// Design box; all coordinates below are expressed inside this square.
    private static let designSize: CGFloat = 20

    static func draw(in rect: CGRect, color: NSColor) {
        guard rect.width > 2, rect.height > 2 else { return }
        let scale = min(rect.width, rect.height) / designSize
        let originX = rect.midX - designSize * scale / 2
        let originY = rect.midY - designSize * scale / 2

        // Design coordinates use y-down for readability; AppKit is y-up.
        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: originX + x * scale, y: originY + (designSize - y) * scale)
        }

        let path = NSBezierPath()
        path.lineWidth = max(1.5, 1.9 * scale)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        // L-shaped axis.
        path.move(to: point(3.1, 3.1))
        path.line(to: point(3.1, 16.9))
        path.move(to: point(3.1, 3.1))
        path.line(to: point(16.9, 3.1))

        // Chart line: the rising, dipping, then higher rising line from the
        // app icon.
        path.move(to: point(6.0, 10.6))
        path.line(to: point(8.9, 6.4))
        path.line(to: point(11.8, 9.0))
        path.line(to: point(16.9, 4.6))

        color.setStroke()
        path.stroke()
    }
}
