import AppKit

/// The four supported HUD anchors. The raw values are persisted.
enum HUDPosition: String, CaseIterable, Identifiable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    var icon: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .bottomLeft: "arrow.down.left"
        case .bottomRight: "arrow.down.right"
        }
    }

    var isRightAnchored: Bool {
        self == .topRight || self == .bottomRight
    }

    func frame(
        for size: CGSize,
        in screen: NSScreen,
        horizontalMargin: CGFloat,
        verticalMargin: CGFloat
    ) -> CGRect {
        frame(
            for: size,
            screenFrame: screen.frame,
            topEdge: screen.visibleFrame.maxY,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin
        )
    }

    /// Pure geometry used by the app and tests.
    ///
    /// The bottom corners are the bottom of the whole display, on either side
    /// of a bottom Dock, not the Dock's visible area. The top edge is the
    /// usable top (below the menu bar). Right-anchored corners are positioned
    /// by their right edge, so a wider HUD grows leftwards and cannot run off
    /// the right side of the screen.
    func frame(
        for size: CGSize,
        screenFrame: CGRect,
        topEdge: CGFloat,
        horizontalMargin: CGFloat = 0,
        verticalMargin: CGFloat = 0
    ) -> CGRect {
        let left = screenFrame.minX + horizontalMargin
        let right = screenFrame.maxX - horizontalMargin
        let bottom = screenFrame.minY + verticalMargin
        let top = topEdge - verticalMargin

        let width = size.width
        let height = size.height

        // Right-anchored corners are positioned by their right edge, so a
        // wider HUD grows leftwards and cannot run off the right side of the
        // screen. Left-anchored corners keep their left edge fixed.
        let x: CGFloat = isRightAnchored
            ? max(screenFrame.minX, right - width)
            : left

        let rawY: CGFloat
        switch self {
        case .topLeft, .topRight:
            rawY = top - height
        case .bottomLeft, .bottomRight:
            rawY = bottom
        }
        // Keep the top edge below the menu bar and the bottom at the display
        // bottom, even with an extreme font scale.
        let y = max(screenFrame.minY, min(rawY, topEdge - height))

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Default HUD placement: bottom-left of the whole display. The size is a
/// starting estimate; the window auto-sizes to its SwiftUI content and is
/// re-anchored after layout.
enum HUDFrame {
    static let defaultSize = CGSize(width: 140, height: 24)

    static func defaultFrame(for screen: NSScreen) -> CGRect {
        HUDPosition.bottomLeft.frame(
            for: defaultSize,
            screenFrame: screen.frame,
            topEdge: screen.visibleFrame.maxY
        )
    }
}
