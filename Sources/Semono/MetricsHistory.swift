import Foundation

@MainActor
final class MetricsHistory: ObservableObject {
    static let shared = MetricsHistory()
    static let maxDataPoints = 30

    struct Snapshot: Equatable {
        let timestamp: Date
        let cpuUsage: Double
        let perCoreCPU: [Double]
        let perCoreFreqMHz: [Double]
        let gpuUsage: Double
        let powerUsage: Double
        let memoryUsage: Double
        let swapBytes: UInt64
        let swapRatio: Double
        let memoryPressureLevel: Int
        let diskReadSpeed: Double
        let diskWriteSpeed: Double
        let thermalState: Int
        let downloadSpeed: Double
        let uploadSpeed: Double
        let wifiRSSI: Int

        /// Value equality deliberately ignores the timestamp so identical
        /// readings collapse into one history point (see `record`).
        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.cpuUsage == rhs.cpuUsage &&
            lhs.perCoreCPU == rhs.perCoreCPU &&
            lhs.perCoreFreqMHz == rhs.perCoreFreqMHz &&
            lhs.gpuUsage == rhs.gpuUsage &&
            lhs.powerUsage == rhs.powerUsage &&
            lhs.memoryUsage == rhs.memoryUsage &&
            lhs.swapBytes == rhs.swapBytes &&
            lhs.swapRatio == rhs.swapRatio &&
            lhs.memoryPressureLevel == rhs.memoryPressureLevel &&
            lhs.diskReadSpeed == rhs.diskReadSpeed &&
            lhs.diskWriteSpeed == rhs.diskWriteSpeed &&
            lhs.thermalState == rhs.thermalState &&
            lhs.downloadSpeed == rhs.downloadSpeed &&
            lhs.uploadSpeed == rhs.uploadSpeed &&
            lhs.wifiRSSI == rhs.wifiRSSI
        }
    }

    @Published var snapshots: [Snapshot] = []

    /// Toggled by the monitor window while it is on screen. History is only
    /// recorded then, so the per-tick snapshot allocation and publish are
    /// skipped entirely while no chart is visible.
    var isRecording = false

    func record(from metrics: MetricsCollector) {
        let snap = Snapshot(
            timestamp: Date(),
            cpuUsage: metrics.cpuUsage,
            perCoreCPU: metrics.perCoreCPU,
            perCoreFreqMHz: metrics.perCoreFreqMHz,
            gpuUsage: metrics.gpuUsage,
            powerUsage: metrics.powerUsage,
            memoryUsage: metrics.memoryUsage,
            swapBytes: metrics.swapBytes,
            swapRatio: metrics.swapRatio,
            memoryPressureLevel: metrics.memoryPressureLevel,
            diskReadSpeed: metrics.diskReadSpeed,
            diskWriteSpeed: metrics.diskWriteSpeed,
            thermalState: metrics.thermalState,
            downloadSpeed: metrics.downloadSpeed,
            uploadSpeed: metrics.uploadSpeed,
            wifiRSSI: metrics.wifiRSSI
        )
        // Skip identical values so a static machine (adaptive sleep) does not
        // publish and re-render the monitor charts pointlessly.
        if let last = snapshots.last, last == snap { return }
        snapshots.append(snap)
        if snapshots.count > Self.maxDataPoints {
            snapshots.removeFirst(snapshots.count - Self.maxDataPoints)
        }
    }
}
