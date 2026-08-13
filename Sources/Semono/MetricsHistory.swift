import Foundation

@MainActor
final class MetricsHistory: ObservableObject {
    static let shared = MetricsHistory()
    static let maxDataPoints = 30

    /// One recorded reading. Equality is delegated to the sample so identical
    /// readings collapse into one history point (see `record`).
    struct Snapshot: Equatable {
        let timestamp: Date
        let sample: Sampler.Sample

        // Forwarding accessors keep the view call sites unchanged; adding a
        // metric only touches `Sample` and these properties.
        var cpuUsage: Double { sample.cpuUsage }
        var perCoreCPU: [Double] { sample.perCoreCPU }
        var perCoreFreqMHz: [Double] { sample.perCoreFreqMHz }
        var gpuUsage: Double { sample.gpuUsage }
        var powerUsage: Double { sample.powerUsage }
        var memoryUsage: Double { sample.memoryUsage }
        var swapBytes: UInt64 { sample.swapBytes }
        var swapRatio: Double { sample.swapRatio }
        var memoryPressureLevel: Int { sample.memoryPressureLevel }
        var diskReadSpeed: Double { sample.diskReadSpeed }
        var diskWriteSpeed: Double { sample.diskWriteSpeed }
        var thermalState: Int { sample.thermalState }
        var downloadSpeed: Double { sample.downloadSpeed }
        var uploadSpeed: Double { sample.uploadSpeed }
        var wifiRSSI: Int { sample.wifiRSSI }
    }

    @Published var snapshots: [Snapshot] = []
    /// Per-core history as columns (one series per core), maintained in step
    /// with `snapshots` so the charts reuse precomputed series instead of
    /// re-mapping the whole history for every core on every tick. Not
    /// `@Published`: `snapshots` is the single invalidation trigger and the
    /// columns are already up to date by the time a view re-evaluates.
    private(set) var perCoreCPUColumns: [[Double]] = []
    private(set) var perCoreFreqColumns: [[Double]] = []

    /// Toggled by the monitor window while it is on screen. History is only
    /// recorded then, so the per-tick snapshot allocation and publish are
    /// skipped entirely while no chart is visible.
    var isRecording = false

    func record(sample: Sampler.Sample) {
        let snap = Snapshot(timestamp: Date(), sample: sample)
        // Skip identical values so a static machine (adaptive sleep) does not
        // publish and re-render the monitor charts pointlessly.
        if let last = snapshots.last, last.sample == snap.sample { return }
        snapshots.append(snap)
        appendColumns(from: snap)
        let overflow = snapshots.count - Self.maxDataPoints
        if overflow > 0 {
            snapshots.removeFirst(overflow)
            perCoreCPUColumns = perCoreCPUColumns.map { Array($0.dropFirst(overflow)) }
            perCoreFreqColumns = perCoreFreqColumns.map { Array($0.dropFirst(overflow)) }
        }
    }

    private func appendColumns(from snap: Snapshot) {
        // New columns start padded with the existing history so every column
        // stays aligned with `snapshots`.
        while perCoreCPUColumns.count < snap.perCoreCPU.count {
            perCoreCPUColumns.append(Array(repeating: 0, count: snapshots.count - 1))
        }
        while perCoreFreqColumns.count < snap.perCoreFreqMHz.count {
            perCoreFreqColumns.append(Array(repeating: 0, count: snapshots.count - 1))
        }
        for i in perCoreCPUColumns.indices {
            perCoreCPUColumns[i].append(i < snap.perCoreCPU.count ? snap.perCoreCPU[i] : 0)
        }
        for i in perCoreFreqColumns.indices {
            perCoreFreqColumns[i].append(i < snap.perCoreFreqMHz.count ? snap.perCoreFreqMHz[i] : 0)
        }
    }
}
