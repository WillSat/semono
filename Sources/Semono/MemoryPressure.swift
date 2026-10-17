import Foundation

/// Maps the raw `kern.memorystatus_vm_pressure_level` value to the app's
/// four-level 0...3 UI scale.
///
/// On macOS the sysctl returns the dispatch note flags, not the internal
/// 0...3 level: 1 = normal, 2 = warning, 4 = critical. The previous mapping
/// treated 1 as "level 1", so a healthy Mac permanently showed a 33% PRS bar
/// and the monitor printed "M". Values 0 and 3 are kept for builds that
/// report the legacy contiguous scale.
enum MemoryPressure {
    static func level(fromRaw raw: Int) -> Int {
        switch raw {
        case 0, 1: return 0   // normal
        case 2: return 1      // warning
        case 3: return 2      // urgent (legacy/alternate)
        case 4: return 3      // critical
        default: return 0
        }
    }
}
