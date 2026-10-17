import Foundation

/// One CPU load counter set, kept as `UInt64` from the moment the kernel
/// values are read. The previous implementation summed per-core `UInt32`
/// ticks in `UInt32` variables; on a 10-core Mac that overflows after about
/// 50 days of uptime and traps in release builds.
struct CPULoad: Sendable, Equatable {
    let used: UInt64
    let total: UInt64

    init(user: UInt64, system: UInt64, nice: UInt64, idle: UInt64) {
        used = user + system + nice
        total = used + idle
    }
}

enum CPUUsage {
    /// Fraction (0...1) between two counter snapshots, or nil when there is
    /// no usable previous snapshot. A counter regression is treated as a
    /// reset instead of producing a negative/overflowed delta.
    static func fraction(previous: CPULoad?, current: CPULoad) -> Double? {
        guard let previous, current.total > previous.total else { return nil }
        let usedDelta = current.used >= previous.used ? current.used - previous.used : 0
        return min(1.0, Double(usedDelta) / Double(current.total - previous.total))
    }
}
