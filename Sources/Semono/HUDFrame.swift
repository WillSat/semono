import AppKit

/// Default HUD placement: the bottom-left corner of the whole display. (The
/// historical "DockDetector" name promised dock avoidance it never
/// implemented; the size here is a placeholder — the window auto-sizes to
/// its SwiftUI content.)
enum HUDFrame {
    static func defaultFrame(for screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: screen.frame.minY, width: 140, height: 24)
    }
}
