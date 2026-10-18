import Testing
@testable import Semono

@MainActor
struct StatusBarMetricTests {
    @Test func legacyRawValuesStillDecode() {
        #expect(StatusBarMetric(rawValue: "cpu") == .cpu)
        #expect(StatusBarMetric(rawValue: "gpu") == .gpu)
        #expect(StatusBarMetric(rawValue: "pwr") == .pwr)
        #expect(StatusBarMetric(rawValue: "memory") == .memory)
    }

    @Test func percentageReadoutsKeepTheTwoLineShape() {
        let metrics = MetricsCollector()
        metrics.cpuUsage = 0.42
        let cpu = StatusBarMetric.cpu.readout(from: metrics)
        #expect(cpu.top == "CPU")
        #expect(cpu.bottom == "42%")
        #expect(!cpu.isIcon)

        let memory = StatusBarMetric.memory.readout(from: metrics)
        #expect(memory.top == "MEM")
        #expect(memory.bottom == "—")
    }

    @Test func pressureReadoutUsesTheThreeStateTag() {
        let metrics = MetricsCollector()
        metrics.memoryPressureLevel = 2
        let critical = StatusBarMetric.pressure.readout(from: metrics)
        #expect(critical.top == "PRS")
        #expect(critical.bottom == "#C")
        #expect(critical.pressureLevel == 2)

        metrics.memoryPressureLevel = 0
        #expect(StatusBarMetric.pressure.readout(from: metrics).bottom == "#N")

        metrics.memoryPressureLevel = nil
        #expect(StatusBarMetric.pressure.readout(from: metrics).bottom == "—")
    }

    @Test func networkReadoutShowsStateSignalAndBothDirections() {
        let metrics = MetricsCollector()
        metrics.networkType = "WiFi"
        metrics.wifiRSSI = -46
        metrics.downloadSpeed = 1_200_000
        metrics.uploadSpeed = 340_000

        let readout = StatusBarMetric.network.readout(from: metrics)
        #expect(readout.top == "WiFi -46")
        #expect(readout.bottom == "↓1.2M ↑340K")
    }

    @Test func offlineNetworkStillProducesAReadout() {
        let metrics = MetricsCollector()
        let readout = StatusBarMetric.network.readout(from: metrics)
        #expect(readout.top == "—")
        #expect(readout.bottom == "↓— ↑—")
    }

    @Test func iconOnlyHasNoText() {
        let metrics = MetricsCollector()
        let readout = StatusBarMetric.icon.readout(from: metrics)
        #expect(readout.isIcon)
        #expect(readout.top.isEmpty)
        #expect(readout.bottom.isEmpty)
        #expect(readout.pressureLevel == nil)
    }

    @Test func everyMetricHasASettingsPresentation() {
        for metric in StatusBarMetric.allCases {
            #expect(!metric.settingsTitleKey.isEmpty)
            #expect(!metric.settingsDescriptionKey.isEmpty)
            #expect(!metric.settingsIcon.isEmpty)
        }
        #expect(Set(StatusBarMetric.allCases.map(\.rawValue)).count == StatusBarMetric.allCases.count)
    }
}

struct StatusBarVisibilityTests {
    @Test func aVisibleAttachedItemIsVisible() {
        #expect(StatusBarVisibility.isVisible(
            itemVisible: true,
            windowExists: true,
            windowVisible: true,
            windowOcclusionVisible: true,
            menuBarOnScreen: true
        ))
    }

    @Test func hiddenItemOrMenuBarIsNotVisible() {
        #expect(!StatusBarVisibility.isVisible(
            itemVisible: false,
            windowExists: true,
            windowVisible: true,
            windowOcclusionVisible: true,
            menuBarOnScreen: true
        ))
        #expect(!StatusBarVisibility.isVisible(
            itemVisible: true,
            windowExists: true,
            windowVisible: true,
            windowOcclusionVisible: true,
            menuBarOnScreen: false
        ))
    }

    @Test func anOrderedOutOrOccludedStatusWindowIsNotVisible() {
        #expect(!StatusBarVisibility.isVisible(
            itemVisible: true,
            windowExists: true,
            windowVisible: false,
            windowOcclusionVisible: true,
            menuBarOnScreen: true
        ))
        #expect(!StatusBarVisibility.isVisible(
            itemVisible: true,
            windowExists: true,
            windowVisible: true,
            windowOcclusionVisible: false,
            menuBarOnScreen: true
        ))
    }

    @Test func anUnattachedWindowDoesNotPauseSampling() {
        #expect(StatusBarVisibility.isVisible(
            itemVisible: true,
            windowExists: false,
            windowVisible: false,
            windowOcclusionVisible: false,
            menuBarOnScreen: true
        ))
    }
}
