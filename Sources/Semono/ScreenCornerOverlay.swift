import AppKit
import CoreGraphics

enum ScreenCornerMode: String, CaseIterable {
    case matchWindows = "window"
    case advanced = "advanced"

    var titleKey: String {
        switch self {
        case .matchWindows: "Match App Windows"
        case .advanced: "Advanced"
        }
    }
}

enum ScreenCornerSettings {
    static let enabledKey = "screenCornersEnabled"
    static let modeKey = "screenCornerMode"
    static let radiusKey = "screenCornerRadius"
    static let curvatureKey = "screenCornerCurvature"
    static let showInFullScreenKey = "screenCornersShowInFullScreen"

    static let defaultRadius = 18.0
    static let defaultCurvature = 4.0
    static let radiusRange = 8.0...40.0
    static let curvatureRange = 1.5...12.0

    /// Effective macOS 27 window corner, including the soft edge/shadow that
    /// sits outside the opaque window content. The mask needs to cover that
    /// edge, not just the content curve, or a gray crescent remains visible.
    static let windowRadius = 30.0
    static let windowCurvature = 4.5
}

enum ScreenCorner {
    case bottomLeft
    case bottomRight
}

/// Owns the two always-on-top corner masks. The masks are shown only while
/// the setting is enabled and follow the built-in display as it moves or
/// changes resolution.
@MainActor
final class ScreenCornerOverlayController {
    static let shared = ScreenCornerOverlayController()

    private var leftWindow: ScreenCornerMaskWindow?
    private var rightWindow: ScreenCornerMaskWindow?
    private var observers: [NSObjectProtocol] = []
    private var hoverTimer: Timer?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        })
        refresh()
    }

    func refresh() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ScreenCornerSettings.enabledKey),
              let screen = builtInScreen
        else {
            removeOverlays()
            return
        }

        let mode = ScreenCornerMode(
            rawValue: defaults.string(forKey: ScreenCornerSettings.modeKey) ?? ""
        ) ?? .matchWindows
        let radius: CGFloat
        let curvature: CGFloat
        switch mode {
        case .matchWindows:
            radius = CGFloat(ScreenCornerSettings.windowRadius)
            curvature = CGFloat(ScreenCornerSettings.windowCurvature)
        case .advanced:
            radius = CGFloat(clamped(
                defaults.object(forKey: ScreenCornerSettings.radiusKey) as? Double
                    ?? ScreenCornerSettings.defaultRadius,
                to: ScreenCornerSettings.radiusRange
            ))
            curvature = CGFloat(clamped(
                defaults.object(forKey: ScreenCornerSettings.curvatureKey) as? Double
                    ?? ScreenCornerSettings.defaultCurvature,
                to: ScreenCornerSettings.curvatureRange
            ))
        }
        let showsInFullScreen = defaults.bool(
            forKey: ScreenCornerSettings.showInFullScreenKey
        )

        if leftWindow == nil {
            leftWindow = ScreenCornerMaskWindow(
                corner: .bottomLeft,
                radius: radius,
                curvature: curvature
            )
        }
        if rightWindow == nil {
            rightWindow = ScreenCornerMaskWindow(
                corner: .bottomRight,
                radius: radius,
                curvature: curvature
            )
        }

        let frame = screen.frame
        leftWindow?.update(
            frame: NSRect(x: frame.minX, y: frame.minY, width: radius, height: radius),
            radius: radius,
            curvature: curvature
        )
        rightWindow?.update(
            frame: NSRect(x: frame.maxX - radius, y: frame.minY, width: radius, height: radius),
            radius: radius,
            curvature: curvature
        )
        leftWindow?.setShowsInFullScreen(showsInFullScreen)
        rightWindow?.setShowsInFullScreen(showsInFullScreen)
        leftWindow?.orderFrontRegardless()
        rightWindow?.orderFrontRegardless()
        startHoverTracking()
    }

    private func removeOverlays() {
        stopHoverTracking()
        leftWindow?.orderOut(nil)
        leftWindow?.close()
        leftWindow = nil
        rightWindow?.orderOut(nil)
        rightWindow?.close()
        rightWindow = nil
    }

    /// The masks must stay click-through, so hover is sampled from the global
    /// pointer location instead of using a tracking area that would consume
    /// clicks. The timer exists only while the effect is enabled.
    private func startHoverTracking() {
        guard hoverTimer == nil else {
            updateHover()
            return
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHover() }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        updateHover()
    }

    private func stopHoverTracking() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func updateHover() {
        let point = NSEvent.mouseLocation
        leftWindow?.updateHover(at: point)
        rightWindow?.updateHover(at: point)
    }

    private var builtInScreen: NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else {
                return false
            }
            return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
        }
    }

    private func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private final class ScreenCornerMaskWindow: NSWindow {
    init(corner: ScreenCorner, radius: CGFloat, curvature: CGFloat) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: radius, height: radius),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        contentView = ScreenCornerMaskView(
            corner: corner,
            radius: radius,
            curvature: curvature
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        // The fake corners are a display effect, never part of a capture.
        sharingType = .none
        level = .screenSaver
        collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
        ]
    }

    private var showsInFullScreen = false

    func setShowsInFullScreen(_ show: Bool) {
        guard show != showsInFullScreen else { return }
        showsInFullScreen = show
        if show {
            collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            collectionBehavior.remove(.fullScreenAuxiliary)
        }
    }



    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private var isHovered = false

    func update(frame: NSRect, radius: CGFloat, curvature: CGFloat) {
        setFrame(frame, display: true)
        guard let view = contentView as? ScreenCornerMaskView else { return }
        view.radius = radius
        view.curvature = curvature
        view.needsDisplay = true
    }

    func updateHover(at screenPoint: NSPoint) {
        let overCorner = frame.contains(screenPoint)
        guard overCorner != isHovered else { return }
        isHovered = overCorner
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = overCorner ? 0 : 1
        }
    }
}

private final class ScreenCornerMaskView: NSView {
    let corner: ScreenCorner
    var radius: CGFloat {
        didSet { needsDisplay = true }
    }
    var curvature: CGFloat {
        didSet { needsDisplay = true }
    }

    init(corner: ScreenCorner, radius: CGFloat, curvature: CGFloat) {
        self.corner = corner
        self.radius = radius
        self.curvature = curvature
        super.init(frame: NSRect(x: 0, y: 0, width: radius, height: radius))
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let path = ScreenCornerGeometry.path(
            in: bounds,
            corner: corner,
            curvature: curvature
        )
        NSColor.black.setFill()
        path.fill()
    }
}

private enum ScreenCornerGeometry {
    /// The corner mask is the region between the screen corner and a
    /// superellipse. Curvature 2 is a circular arc; higher values approach a
    /// squircle, matching the continuous curve of the built-in display.
    static func path(
        in rect: NSRect,
        corner: ScreenCorner,
        curvature: CGFloat
    ) -> NSBezierPath {
        let radius = min(rect.width, rect.height)
        guard radius > 0 else { return NSBezierPath() }

        let exponent = max(1.5, curvature)
        let power = 2.0 / exponent
        let path = NSBezierPath()

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            let px = corner == .bottomLeft ? x : radius - x
            return NSPoint(x: rect.minX + px, y: rect.minY + y)
        }

        path.move(to: point(0, 0))
        path.line(to: point(radius, 0))

        let steps = 72
        for index in 0...steps {
            let t = CGFloat.pi / 2 * CGFloat(index) / CGFloat(steps)
            let x = radius - radius * pow(sin(t), power)
            let y = radius - radius * pow(cos(t), power)
            path.line(to: point(x, y))
        }

        path.line(to: point(0, radius))
        path.close()
        return path
    }
}
