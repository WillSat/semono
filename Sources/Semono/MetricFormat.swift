import Foundation

/// Shared metric formatting. The HUD pads to a fixed field width so its
/// columns do not jitter, while the monitor window uses compact labels; both
/// sets live here instead of being re-derived per view.
enum MetricFormat {
    // MARK: Monitor window (compact)

    /// 500M / 1.2G style, for absolute byte counts.
    static func bytesCompact(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1fG", bytes / 1_000_000_000)
        } else {
            return String(format: "%.0fM", bytes / 1_000_000)
        }
    }

    /// 999B / 1.2K / 34M style, for per-second rates.
    static func speedCompact(_ bytesPerSec: Double) -> String {
        guard bytesPerSec >= 0 else { return "0B" }
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0fK", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0fB", bytesPerSec)
        }
    }

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

    private static func pad(_ s: String, to width: Int) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }
}
