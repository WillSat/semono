import Foundation

/// Maps the raw `kern.memorystatus_vm_pressure_level` value to the three
/// levels macOS actually exposes: normal, warning, critical.
///
/// On macOS the sysctl returns the dispatch note flags, not the internal
/// 0...3 level: 1 = normal, 2 = warning, 4 = critical. The old four-level UI
/// mapped normal (1) to "level 1" and left a third "H" state that the current
/// sysctl never returns; this type now has one honest slot per kernel state.
enum MemoryPressure {
    static func level(fromRaw raw: Int) -> Int {
        switch raw {
        case 0, 1: return 0   // normal
        case 2, 3: return 1   // warning; 3 is the legacy urgent value
        case 4: return 2      // critical
        default: return 0
        }
    }

    /// Compact English abbreviation shown after the indicator dot.
    static func abbreviation(for level: Int) -> String {
        switch level {
        case 0: return "N"
        case 1: return "W"
        default: return "C"
        }
    }
}
