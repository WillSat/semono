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
    }

    @Published var snapshots: [Snapshot] = []

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
        snapshots.append(snap)
        if snapshots.count > Self.maxDataPoints {
            snapshots.removeFirst(snapshots.count - Self.maxDataPoints)
        }
    }
}
