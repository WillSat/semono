import Foundation

enum RateMath {
    /// Bytes per second between two monotonic counter reads. A counter
    /// regression, a zero/negative interval, or a missing baseline is
    /// reported as nil (unavailable) rather than a fabricated zero.
    static func bytesPerSecond(previous: UInt64, current: UInt64, seconds: Double) -> Double? {
        guard seconds > 0, current >= previous else { return nil }
        return Double(current - previous) / seconds
    }

    /// Seconds between two monotonic nanosecond timestamps.
    static func seconds(from start: UInt64, to end: UInt64) -> Double? {
        guard start > 0, end >= start else { return nil }
        return Double(end - start) / 1_000_000_000.0
    }
}
