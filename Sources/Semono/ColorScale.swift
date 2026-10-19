import SwiftUI

enum ColorScale {
    /// App-wide accent (the cyan end of the heat scale).
    static let accent = Color(nsColor: NSColor(hex: 0x4FC3F7))

    private static let anchors: [(Double, NSColor)] = [
        (0.0,  NSColor(hex: 0x4FC3F7).usingColorSpace(.sRGB) ?? NSColor(hex: 0x4FC3F7)),
        (0.25, NSColor(hex: 0x66BB6A).usingColorSpace(.sRGB) ?? NSColor(hex: 0x66BB6A)),
        (0.5,  NSColor(hex: 0xFFEE58).usingColorSpace(.sRGB) ?? NSColor(hex: 0xFFEE58)),
        (0.75, NSColor(hex: 0xFFA726).usingColorSpace(.sRGB) ?? NSColor(hex: 0xFFA726)),
        (1.0,  NSColor(hex: 0xEF5350).usingColorSpace(.sRGB) ?? NSColor(hex: 0xEF5350)),
    ]

    /// Darker anchors for a white HUD background, preserving the same
    /// blue → green → yellow → orange → red progression.
    private static let lightAnchors: [(Double, NSColor)] = [
        (0.0,  NSColor(hex: 0x1E88E5).usingColorSpace(.sRGB) ?? NSColor(hex: 0x1E88E5)),
        (0.25, NSColor(hex: 0x388E3C).usingColorSpace(.sRGB) ?? NSColor(hex: 0x388E3C)),
        (0.5,  NSColor(hex: 0xB8860B).usingColorSpace(.sRGB) ?? NSColor(hex: 0xB8860B)),
        (0.75, NSColor(hex: 0xE65100).usingColorSpace(.sRGB) ?? NSColor(hex: 0xE65100)),
        (1.0,  NSColor(hex: 0xD32F2F).usingColorSpace(.sRGB) ?? NSColor(hex: 0xD32F2F)),
    ]

    /// Precomputed 0–100% palettes, built once from the anchors. Lookup is a
    /// single array index — no interpolation or NSColor bridging at render time.
    static let palette: [Color] = (0...100).map { interpolate(Double($0) / 100.0, anchors: anchors) }
    static let lightPalette: [Color] = (0...100).map { interpolate(Double($0) / 100.0, anchors: lightAnchors) }

    static func color(for usage: Double, light: Bool = false) -> Color {
        let table = light ? lightPalette : palette
        return table[Int((max(0, min(1, usage)) * 100.0).rounded())]
    }

    private static func interpolate(_ t: Double, anchors: [(Double, NSColor)]) -> Color {
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

    static func color(forLevel level: Int, light: Bool = false) -> Color {
        let t: Double
        switch level {
        case 0: t = 0.0
        case 1: t = 0.33
        case 2: t = 0.66
        default: t = 1.0
        }
        return color(for: t, light: light)
    }

    /// Three-state memory pressure palette: green normal, orange warning,
    /// red critical. Used by the PRS indicator dot and abbreviation.
    static func color(forPressureLevel level: Int, light: Bool = false) -> Color {
        switch level {
        case 0: return color(for: 0.25, light: light)
        case 1: return color(for: 0.66, light: light)
        default: return color(for: 1.0, light: light)
        }
    }

    /// 0..1 strength for an RSSI value. RSSI is negative dBm where -30 is
    /// excellent and -90 is unusable; 0 means "unavailable" and maps to 0.
    static func normalizedRSSI(_ rssi: Int) -> Double {
        Double(max(30, min(90, abs(rssi))) - 30) / 60.0
    }

    static func color(forRSSI rssi: Int, light: Bool = false) -> Color {
        color(for: normalizedRSSI(rssi), light: light)
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
