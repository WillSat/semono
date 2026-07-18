import AppKit

enum DockDetector {

    static func defaultFrame(for screen: NSScreen) -> CGRect {
        let margin: CGFloat = 6
        let w: CGFloat = 140
        let h: CGFloat = 24
        return CGRect(
            x: screen.visibleFrame.maxX - w - margin,
            y: screen.visibleFrame.minY + margin,
            width: w, height: h
        )
    }
}
