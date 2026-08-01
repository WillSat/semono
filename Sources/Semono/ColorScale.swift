import SwiftUI

enum ColorScale {
    /// App-wide accent (the cyan end of the heat scale).
    static let accent = Color(nsColor: NSColor(hex: 0x4FC3F7))

    private static let anchors: [(Double, NSColor)] = [
        (0.0,  NSColor(hex: 0x4FC3F7).usingColorSpace(.sRGB)!),
        (0.25, NSColor(hex: 0x66BB6A).usingColorSpace(.sRGB)!),
        (0.5,  NSColor(hex: 0xFFEE58).usingColorSpace(.sRGB)!),
        (0.75, NSColor(hex: 0xFFA726).usingColorSpace(.sRGB)!),
        (1.0,  NSColor(hex: 0xEF5350).usingColorSpace(.sRGB)!),
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

    static func color(forLevel level: Int) -> Color {
        let t: Double
        switch level {
        case 0: t = 0.0
        case 1: t = 0.33
        case 2: t = 0.66
        default: t = 1.0
        }
        return color(for: t)
    }

    static func color(forRSSI rssi: Int) -> Color {
        let norm = Double(max(30, min(90, abs(rssi))) - 30) / 60.0
        return color(for: norm)
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
        let u = max(0, min(1, t))
        let r = a.redComponent   + (b.redComponent   - a.redComponent)   * u
        let g = a.greenComponent + (b.greenComponent - a.greenComponent) * u
        let bl = a.blueComponent + (b.blueComponent  - a.blueComponent)  * u
        return NSColor(red: r, green: g, blue: bl, alpha: 1.0)
    }
}
