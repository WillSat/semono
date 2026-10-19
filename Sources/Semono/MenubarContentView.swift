import AppKit

/// Custom-drawn status bar readout. Drawn text (instead of NSTextField
/// subviews) means no tracking areas or cursor rects live in the menu bar
/// region, and updates only invalidate the layer instead of re-snapshotting
/// AppKit text views every tick.
///
/// Text mode draws the tiny metric label above the value, as before. Icon mode
/// draws the monochrome Semono mark and nothing else; network mode uses the
/// same two-line frame for connection state plus up/down speed.
final class MenubarContentView: NSView {
    var readout: StatusBarReadout = StatusBarReadout() {
        didSet {
            guard readout != oldValue else { return }
            needsDisplay = true
            rebuildCachedStrings()
            updateAccessibility()
        }
    }

    /// While an update check is in flight the status item becomes a small
    /// spinner instead of the user's chosen metric.
    var isChecking = false {
        didSet {
            guard isChecking != oldValue else { return }
            if isChecking {
                startSpinning()
            } else {
                stopSpinning()
            }
            needsDisplay = true
            updateAccessibility()
        }
    }

    private var spinTimer: Timer?
    private var spinAngle: CGFloat = 0

    // Fonts are created once and held for the app's lifetime. Realizing a
    // font lazily during measurement (CTLineCreateWithAttributedString) can
    // crash CoreText under memory pressure — it built a font-trait dictionary
    // containing nil and aborted the process — so the CTFont objects are
    // never realized at layout time.
    private static let valueFont = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold)
    private static let typeFont = NSFont.systemFont(ofSize: 7, weight: .medium)

    /// Horizontal padding around the widest measured string.
    private static let widthPadding: CGFloat = 10
    /// Status bar length for the icon-only mode.
    private static let iconWidth: CGFloat = 28

    // Text uses the system label color, resolved against the effective
    // appearance so it follows the macOS light/dark menu bar automatically.
    // A dynamic color is resolved to a concrete value here instead of being
    // handed to CoreText unresolved; color never enters the measurement
    // path, and the draw path gets the appearance-correct value.
    private var textColor: NSColor
    private var valueColor: NSColor

    // Strings are built and measured only when the readout or the effective
    // appearance changes, so the per-tick draw path allocates nothing.
    private var cachedTopString: NSAttributedString?
    private var cachedBottomString: NSAttributedString?
    private var cachedTopSize: NSSize = .zero
    private var cachedBottomSize: NSSize = .zero

    override init(frame frameRect: NSRect) {
        textColor = Self.resolvedLabelColor(for: NSApp.effectiveAppearance)
        valueColor = textColor
        super.init(frame: frameRect)
        wantsLayer = true
        rebuildCachedStrings()
        updateAccessibility()
    }

    required init?(coder: NSCoder) {
        textColor = Self.resolvedLabelColor(for: NSApp.effectiveAppearance)
        valueColor = textColor
        super.init(coder: coder)
        wantsLayer = true
        rebuildCachedStrings()
        updateAccessibility()
    }

    private func rebuildCachedStrings() {
        guard !readout.isIcon else {
            cachedTopString = nil
            cachedBottomString = nil
            cachedTopSize = .zero
            cachedBottomSize = .zero
            return
        }

        valueColor = Self.color(
            forPressureLevel: readout.pressureLevel,
            label: textColor,
            appearance: effectiveAppearance
        )
        cachedTopString = NSAttributedString(
            string: readout.top,
            attributes: [.font: Self.typeFont, .foregroundColor: textColor]
        )
        cachedBottomString = NSAttributedString(
            string: readout.bottom,
            attributes: [.font: Self.valueFont, .foregroundColor: valueColor]
        )
        cachedTopSize = cachedTopString?.size() ?? .zero
        cachedBottomSize = cachedBottomString?.size() ?? .zero
    }

    /// Width required by the currently displayed content.
    var fittingWidth: CGFloat {
        if isChecking { return 24 }
        if readout.isIcon { return Self.iconWidth }
        return ceil(max(cachedTopSize.width, cachedBottomSize.width)) + Self.widthPadding
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: fittingWidth, height: NSStatusBar.system.thickness)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        textColor = Self.resolvedLabelColor(for: effectiveAppearance)
        rebuildCachedStrings()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isChecking {
            drawSpinner()
            return
        }

        if readout.isIcon {
            let side = min(bounds.height - 2, 20)
            let rect = NSRect(
                x: bounds.midX - side / 2,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            )
            SemonoMark.draw(in: rect, color: textColor)
            return
        }

        guard let top = cachedTopString, let bottom = cachedBottomString else { return }

        let maxWidth = max(cachedTopSize.width, cachedBottomSize.width)
        let x = (bounds.width - maxWidth) / 2
        let totalHeight = cachedBottomSize.height + cachedTopSize.height - 1
        let y = (bounds.height - totalHeight) / 2

        // AppKit's y axis is bottom-up here: draw the value on the lower line
        // first, then the tiny type label above it.
        bottom.draw(at: NSPoint(x: x, y: y))
        top.draw(at: NSPoint(x: x, y: y + cachedBottomSize.height - 1))
    }

    override func mouseDown(with event: NSEvent) {
        showMenu()
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    private func updateAccessibility() {
        setAccessibilityRole(.button)
        setAccessibilityLabel(
            isChecking
                ? LocaleManager.shared.localized("Checking for Updates…")
                : readout.accessibility
        )
    }

    private func startSpinning() {
        stopSpinning()
        spinAngle = 0
        let timer = Timer(
            timeInterval: 1.0 / 30.0,
            target: self,
            selector: #selector(tickSpinner),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        spinTimer = timer
    }

    @objc private func tickSpinner() {
        spinAngle += .pi / 9
        if spinAngle >= .pi * 2 { spinAngle -= .pi * 2 }
        needsDisplay = true
    }

    private func stopSpinning() {
        spinTimer?.invalidate()
        spinTimer = nil
        spinAngle = 0
    }

    private func drawSpinner() {
        let side = min(bounds.height - 6, 14)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: side / 2,
            startAngle: spinAngle * 180 / .pi,
            endAngle: (spinAngle + .pi * 1.5) * 180 / .pi,
            clockwise: false
        )
        path.lineWidth = 1.7
        path.lineCapStyle = .round
        textColor.setStroke()
        path.stroke()
    }

    /// Pops the menu up below the item. The status bar window uses a flipped
    /// coordinate system, so `y = bounds.height + 5` places the menu's top
    /// edge just beneath the item (`.zero` would anchor it over the item
    /// itself and left-align it instead of centering under the readout).
    private func showMenu() {
        guard let menu else { return }
        // Activating the accessory app before the menu opens keeps its
        // programmatic menu items rendered as enabled (Settings, Check for
        // Updates) instead of the inactive-app dimming.
        NSApp.activate()
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

    /// Warnings are the one place the menu bar readout uses colour, matching
    /// the HUD's pressure semantics without turning every metric into a tinted
    /// item. Normal pressure and all other metrics use the menu bar label
    /// colour, so the item keeps following light/dark menu bars.
    private static func color(
        forPressureLevel level: Int?,
        label: NSColor,
        appearance: NSAppearance
    ) -> NSColor {
        switch level {
        case 1: resolved(.systemOrange, for: appearance)
        case 2: resolved(.systemRed, for: appearance)
        default: label
        }
    }

    private static func resolved(_ color: NSColor, for appearance: NSAppearance) -> NSColor {
        var resolved = color
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

}
