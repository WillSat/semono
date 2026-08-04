import AppKit

/// Custom-drawn status bar readout. Drawn text (instead of NSTextField
/// subviews) means no tracking areas or cursor rects live in the menu bar
/// region, and updates only invalidate the layer instead of re-snapshotting
/// AppKit text views every tick.
final class MenubarContentView: NSView {
    var displayText: String = "" {
        didSet {
            if displayText != oldValue { needsDisplay = true }
        }
    }
    var displayType: String = "CPU" {
        didSet {
            if displayType != oldValue { needsDisplay = true }
        }
    }

    private var valueAttrs: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    private var typeAttrs: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 6.5, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]
    }

    /// Width required by the currently displayed content.
    var fittingWidth: CGFloat {
        let valueW = NSAttributedString(string: displayText, attributes: valueAttrs).size().width
        let typeW = NSAttributedString(string: displayType, attributes: typeAttrs).size().width
        return ceil(max(valueW, typeW)) + 10
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fittingWidth, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let value = NSAttributedString(string: displayText, attributes: valueAttrs)
        let type = NSAttributedString(string: displayType, attributes: typeAttrs)
        let valueSize = value.size()
        let typeSize = type.size()

        let maxWidth = max(valueSize.width, typeSize.width)
        let x = (bounds.width - maxWidth) / 2
        let totalHeight = valueSize.height + typeSize.height - 1
        let y = (bounds.height - totalHeight) / 2

        type.draw(at: NSPoint(x: x, y: y))
        value.draw(at: NSPoint(x: x, y: y + typeSize.height - 1))
    }

    override func mouseDown(with event: NSEvent) {
        if let menu = self.menu {
            menu.popUp(positioning: nil, at: .zero, in: self)
        }
    }
}
