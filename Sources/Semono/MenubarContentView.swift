import AppKit

/// Custom-drawn status bar readout. Drawn text (instead of NSTextField
/// subviews) means no tracking areas or cursor rects live in the menu bar
/// region, and updates only invalidate the layer instead of re-snapshotting
/// AppKit text views every tick.
///
/// In adaptive-sleep mode the value line sits on a compact macOS-styled
/// badge (system-tinted, appearance-aware) that hugs the value text only;
/// the type line below stays on the plain bar.
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

    /// Adaptive-sleep badge: value line on a tinted rounded capsule.
    var isSleeping: Bool = false {
        didSet {
            if isSleeping != oldValue { needsDisplay = true }
        }
    }

    private var isDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var valueAttrs: [NSAttributedString.Key: Any] {
        let color: NSColor
        if isSleeping {
            color = isDarkMode ? NSColor.labelColor : NSColor.white.withAlphaComponent(0.92)
        } else {
            color = NSColor.labelColor
        }
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: color,
        ]
    }

    private var typeAttrs: [NSAttributedString.Key: Any] {
        [
            .font: NSFont.systemFont(ofSize: 6.5, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
    }

    /// Width required by the currently displayed content. Sleeping adds
    /// padding for the badge around the value text only.
    var fittingWidth: CGFloat {
        let valueW = NSAttributedString(string: displayText, attributes: valueAttrs).size().width
        let typeW = NSAttributedString(string: displayType, attributes: typeAttrs).size().width
        let valueBadgeW = valueW + (isSleeping ? 8 : 0)
        return ceil(max(valueBadgeW, typeW)) + (isSleeping ? 8 : 10)
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
        let valueY = y + typeSize.height - 1

        if isSleeping {
            let badgeRect = NSRect(
                x: x - 4,
                y: valueY - 1.25,
                width: valueSize.width + 8,
                height: valueSize.height + 2.5
            )
            let bg = isDarkMode
                ? NSColor.white.withAlphaComponent(0.15)
                : NSColor.black.withAlphaComponent(0.85)
            let badge = NSBezierPath(
                roundedRect: badgeRect,
                xRadius: 4,
                yRadius: 4
            )
            bg.setFill()
            badge.fill()
        }

        type.draw(at: NSPoint(x: x, y: y))
        value.draw(at: NSPoint(x: x, y: valueY))
    }

    override func mouseDown(with event: NSEvent) {
        if let menu = self.menu {
            menu.popUp(positioning: nil, at: .zero, in: self)
        }
    }
}
