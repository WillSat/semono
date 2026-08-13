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
                rebuildCachedStrings()
            }
        }
    }
    var displayType: String = "CPU" {
        didSet {
            if displayType != oldValue {
                needsDisplay = true
                rebuildCachedStrings()
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

    /// Horizontal padding around the widest measured string.
    private static let widthPadding: CGFloat = 10

    // Text uses the system label color, resolved against the effective
    // appearance so it follows the macOS light/dark menu bar automatically.
    // A dynamic color is resolved to a concrete value here instead of being
    // handed to CoreText unresolved; color never enters the measurement
    // path, and the draw path gets the appearance-correct value.
    private var textColor: NSColor

    // Strings are built and measured only when the text, type, or effective
    // appearance changes, so the per-tick draw path allocates nothing.
    private var cachedValueString: NSAttributedString?
    private var cachedTypeString: NSAttributedString?
    private var cachedValueSize: NSSize = .zero
    private var cachedTypeSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        textColor = Self.resolvedLabelColor(for: NSApp.effectiveAppearance)
        super.init(frame: frameRect)
        rebuildCachedStrings()
    }

    required init?(coder: NSCoder) {
        textColor = Self.resolvedLabelColor(for: NSApp.effectiveAppearance)
        super.init(coder: coder)
        rebuildCachedStrings()
    }

    private func rebuildCachedStrings() {
        cachedValueString = NSAttributedString(
            string: displayText,
            attributes: [.font: Self.valueFont, .foregroundColor: textColor]
        )
        cachedTypeString = NSAttributedString(
            string: displayType,
            attributes: [.font: Self.typeFont, .foregroundColor: textColor]
        )
        cachedValueSize = cachedValueString?.size() ?? .zero
        cachedTypeSize = cachedTypeString?.size() ?? .zero
    }

    /// Width required by the currently displayed content.
    var fittingWidth: CGFloat {
        ceil(max(cachedValueSize.width, cachedTypeSize.width)) + Self.widthPadding
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fittingWidth, height: NSStatusBar.system.thickness)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = Self.resolvedLabelColor(for: effectiveAppearance)
        rebuildCachedStrings()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let value = cachedValueString, let type = cachedTypeString else { return }

        let maxWidth = max(cachedValueSize.width, cachedTypeSize.width)
        let x = (bounds.width - maxWidth) / 2
        let totalHeight = cachedValueSize.height + cachedTypeSize.height - 1
        let y = (bounds.height - totalHeight) / 2

        type.draw(at: NSPoint(x: x, y: y))
        value.draw(at: NSPoint(x: x, y: y + cachedTypeSize.height - 1))
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
