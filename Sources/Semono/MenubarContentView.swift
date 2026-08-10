import AppKit

/// Custom-drawn status bar readout. Drawn text (instead of NSTextField
/// subviews) means no tracking areas or cursor rects live in the menu bar
/// region, and updates only invalidate the layer instead of re-snapshotting
/// AppKit text views every tick.
final class MenubarContentView: NSView {
    var displayText: String = "" {
        didSet {
            if displayText != oldValue {
                needsDisplay = true
                invalidateWidths()
            }
        }
    }
    var displayType: String = "CPU" {
        didSet {
            if displayType != oldValue {
                needsDisplay = true
                invalidateWidths()
            }
        }
    }

    // Fonts are created once and held for the app's lifetime. Realizing a
    // font lazily during measurement (CTLineCreateWithAttributedString) can
    // crash CoreText under memory pressure — it built a font-trait dictionary
    // containing nil and aborted the process — so the CTFont objects are
    // never realized at layout time.
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    private static let typeFont = NSFont.systemFont(ofSize: 6.5, weight: .medium)

    // Text uses the system label color, resolved against the effective
    // appearance so it follows the macOS light/dark menu bar automatically.
    // A dynamic color is resolved to a concrete value here instead of being
    // handed to CoreText unresolved; color never enters the measurement
    // path, and the draw path gets the appearance-correct value.
    private var textColor: NSColor

    // Measured widths are cached and only recomputed when the displayed text
    // or type changes, so AppKit layout never re-runs text measurement.
    private var valueWidth: CGFloat?
    private var typeWidth: CGFloat?

    override init(frame frameRect: NSRect) {
        textColor = Self.resolvedLabelColor(for: NSApp.effectiveAppearance)
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        textColor = Self.resolvedLabelColor(for: NSApp.effectiveAppearance)
        super.init(coder: coder)
    }

    /// Font-only attributes for measurement — no color involved in sizing.
    private var measureValueAttrs: [NSAttributedString.Key: Any] {
        [.font: Self.valueFont]
    }

    private var measureTypeAttrs: [NSAttributedString.Key: Any] {
        [.font: Self.typeFont]
    }

    private var drawValueAttrs: [NSAttributedString.Key: Any] {
        [.font: Self.valueFont, .foregroundColor: textColor]
    }

    private var drawTypeAttrs: [NSAttributedString.Key: Any] {
        [.font: Self.typeFont, .foregroundColor: textColor]
    }

    /// Width required by the currently displayed content.
    var fittingWidth: CGFloat {
        if valueWidth == nil {
            valueWidth = NSAttributedString(string: displayText, attributes: measureValueAttrs).size().width
        }
        if typeWidth == nil {
            typeWidth = NSAttributedString(string: displayType, attributes: measureTypeAttrs).size().width
        }
        return ceil(max(valueWidth ?? 0, typeWidth ?? 0)) + 10
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fittingWidth, height: NSStatusBar.system.thickness)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = Self.resolvedLabelColor(for: effectiveAppearance)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let value = NSAttributedString(string: displayText, attributes: drawValueAttrs)
        let type = NSAttributedString(string: displayType, attributes: drawTypeAttrs)
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
        showMenu()
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    /// Pops the menu up below the item. The status bar window uses a flipped
    /// coordinate system, so `y = bounds.height + 5` places the menu's top
    /// edge just beneath the item (`.zero` would anchor it over the item
    /// itself and left-align it instead of centering under the readout).
    private func showMenu() {
        guard let menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 5), in: self)
    }

    private func invalidateWidths() {
        valueWidth = nil
        typeWidth = nil
    }

    /// Resolves the dynamic label color against a specific appearance so the
    /// text follows the macOS light/dark menu bar while remaining a concrete
    /// (non-dynamic) color for drawing.
    private static func resolvedLabelColor(for appearance: NSAppearance) -> NSColor {
        var resolved = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            let color = NSColor.labelColor
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }
}
