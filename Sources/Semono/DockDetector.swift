import AppKit

enum DockDetector {

    /// Default HUD frame: bottom-left corner of the whole display. The size
    /// is a placeholder — the window auto-sizes to its SwiftUI content.
    static func defaultFrame(for screen: NSScreen) -> CGRect {
        CGRect(x: screen.frame.minX, y: screen.frame.minY, width: 140, height: 24)
    }
}
