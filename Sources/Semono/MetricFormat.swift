import Foundation

/// Shared HUD formatting. Values are padded to a fixed field width so the
/// columns do not jitter when a digit count changes.
enum MetricFormat {
    // MARK: HUD (fixed width)

    /// Swap usage, right-padded to a 4-character field.
    static func swap(_ bytes: UInt64) -> String {
        let raw: String
        if bytes >= 1_000_000_000 {
            raw = String(format: "%.1fG", Double(bytes) / 1_000_000_000)
        } else if bytes >= 1_000_000 {
            raw = String(format: "%.0fM", Double(bytes) / 1_000_000)
        } else if bytes >= 1_000 {
            raw = String(format: "%.0fK", Double(bytes) / 1_000)
        } else {
            raw = "\(bytes)B"
        }
        return pad(raw, to: 4)
    }

    /// Throughput, right-padded to a 5-character field.
    static func speed(_ bytesPerSec: Double) -> String {
        let raw: String
        guard bytesPerSec >= 0 else { return pad("0B", to: 5) }
        if bytesPerSec >= 1_000_000 {
            raw = String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 10_000 {
            raw = String(format: "%dK", Int(bytesPerSec / 1_000))
        } else if bytesPerSec >= 1_000 {
            raw = String(format: "%.1fK", bytesPerSec / 1_000)
        } else {
            raw = String(format: "%dB", Int(bytesPerSec))
        }
        return pad(raw, to: 5)
    }

    /// Power draw in watts, one decimal.
    static func power(_ watts: Double) -> String {
        String(format: "%.1f", watts)
    }

    /// Placeholder for an unavailable metric, padded to the same fixed field
    /// width as the live value so the HUD columns do not jitter.
    static func dash(_ width: Int) -> String {
        pad("\u{2014}", to: width)
    }

    private static func pad(_ s: String, to width: Int) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }
}
