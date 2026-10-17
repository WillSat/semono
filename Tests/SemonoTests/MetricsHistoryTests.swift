import Testing
@testable import Semono

@MainActor
struct MetricsHistoryTests {
    @Test func keepsThirtyPointsAndAlignedColumns() {
        let history = MetricsHistory()
        for i in 0..<35 {
            var sample = Sampler.Sample()
            sample.cpuUsage = Double(i)
            sample.gpuUsage = i.isMultiple(of: 2) ? nil : 0.5
            sample.perCoreCPU = [Double(i), Double(i) / 2]
            sample.perCoreFreqMHz = [1_000, 2_000]
            history.record(sample: sample)
        }
        #expect(history.snapshots.count == MetricsHistory.maxDataPoints)
        #expect(history.snapshots.last?.cpuUsage == 34)
        #expect(history.snapshots.contains { $0.gpuUsage == nil })
        #expect(history.perCoreCPUColumns.count == 2)
        #expect(history.perCoreCPUColumns.allSatisfy { $0.count == MetricsHistory.maxDataPoints })
        #expect(history.perCoreFreqColumns.allSatisfy { $0.count == MetricsHistory.maxDataPoints })
    }

    @Test func identicalSamplesCollapse() {
        let history = MetricsHistory()
        var sample = Sampler.Sample()
        sample.memoryUsage = 0.5
        history.record(sample: sample)
        history.record(sample: sample)
        #expect(history.snapshots.count == 1)
    }

    @Test func missingPerCoreDataClearsColumnsInsteadOfAppendingZeros() {
        let history = MetricsHistory()
        var sample = Sampler.Sample()
        sample.cpuUsage = 0.1
        sample.perCoreCPU = [0.1, 0.2]
        sample.perCoreFreqMHz = [1_000, 2_000]
        history.record(sample: sample)
        #expect(history.perCoreCPUColumns.count == 2)

        sample.cpuUsage = 0.2
        sample.perCoreCPU = []
        sample.perCoreFreqMHz = []
        history.record(sample: sample)
        #expect(history.perCoreCPUColumns.isEmpty)
        #expect(history.perCoreFreqColumns.isEmpty)
    }
}
