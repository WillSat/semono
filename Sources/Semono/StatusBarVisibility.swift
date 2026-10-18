import AppKit
import CoreGraphics

/// Whether the app's status item is actually on screen. The menu bar can be
/// hidden by a full-screen Space (or by the user's auto-hide setting) even
/// though the item still exists, so `NSStatusItem.isVisible` alone is not the
/// answer. The status item's window reports visibility/occlusion, and the
/// window server's menu bar window is used as a second signal for the
/// full-screen case.
enum StatusBarVisibility {
    /// Pure decision used by the app and by tests. A missing window is treated
    /// as visible: an item that has not been attached yet must not pause
    /// sampling.
    static func isVisible(
        itemVisible: Bool,
        windowExists: Bool,
        windowVisible: Bool,
        windowOcclusionVisible: Bool,
        menuBarOnScreen: Bool
    ) -> Bool {
        guard itemVisible else { return false }
        guard menuBarOnScreen else { return false }
        if windowExists {
            guard windowVisible, windowOcclusionVisible else { return false }
        }
        return true
    }
}

/// Finds the window server's menu bar window. Only window metadata is read
/// (bounds/layer/alpha), which needs no screen-recording permission.
enum MenuBarProbe {
    /// Layer 24 is the menu bar's window level. The height/alpha checks keep
    /// unrelated overlay windows from being mistaken for it.
    static func isOnScreen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]], !windows.isEmpty else {
            // If the window server cannot answer, assume the bar is visible:
            // pausing live data is worse than sampling a little extra.
            return true
        }

        let widestScreen = NSScreen.screens.map(\.frame.width).max() ?? 0
        return windows.contains { window in
            // 24 is the window server's menu bar; 25 is MenuBarAgent, which
            // appears alongside it during some transitions.
            guard let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 24 || layer == 25 else {
                return false
            }
            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
            guard alpha > 0.5 else { return false }

            let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
            let y = bounds["Y"] as? Double ?? -1
            let height = bounds["Height"] as? Double ?? 0
            let width = bounds["Width"] as? Double ?? 0
            return y <= 1
                && height >= 18
                && height <= 80
                && width >= max(500, widestScreen * 0.5)
        }
    }
}
