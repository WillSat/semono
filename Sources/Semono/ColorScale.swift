import SwiftUI

enum ColorScale {
    private static let anchors: [(Double, NSColor)] = [
        (0.0,  NSColor(hex: 0x4FC3F7)),
        (0.25, NSColor(hex: 0x66BB6A)),
        (0.5,  NSColor(hex: 0xFFEE58)),
        (0.75, NSColor(hex: 0xFFA726)),
        (1.0,  NSColor(hex: 0xEF5350)),
    ]

    static func color(for usage: Double) -> Color {
        let t = max(0, min(1, usage))

        var lower = anchors[0]
        var upper = anchors[anchors.count - 1]
        for i in 0..<(anchors.count - 1) {
            if t >= anchors[i].0 && t <= anchors[i + 1].0 {
                lower = anchors[i]
                upper = anchors[i + 1]
                break
            }
        }

        let range = upper.0 - lower.0
        let localT = range > 0 ? (t - lower.0) / range : 0
        return Color(nsColor: NSColor.lerp(lower.1, upper.1, CGFloat(localT)))
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    static func lerp(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
        let t = max(0, min(1, t))
        guard let aRGB = a.usingColorSpace(.sRGB),
              let bRGB = b.usingColorSpace(.sRGB) else { return a }
        let r = aRGB.redComponent   + (bRGB.redComponent   - aRGB.redComponent)   * t
        let g = aRGB.greenComponent + (bRGB.greenComponent - aRGB.greenComponent) * t
        let bl = aRGB.blueComponent + (bRGB.blueComponent  - aRGB.blueComponent)  * t
        return NSColor(red: r, green: g, blue: bl, alpha: 1.0)
    }
}
