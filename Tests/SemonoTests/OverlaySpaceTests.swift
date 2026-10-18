import Testing
@testable import Semono

/// The overlay's Space membership is the whole of the "show in fullscreen"
/// setting: macOS gives each full-screen app a Space of its own, and these two
/// flags are what decide whether the HUD is allowed on it. Everything else is
/// the window server's business.
struct OverlaySpacePolicyTests {
    @Test func overlayOnJoinsFullScreenSpaces() {
        let on = OverlaySpacePolicy.collectionBehavior(showInFullscreen: true)
        #expect(on.contains(.fullScreenAuxiliary))
        #expect(!on.contains(.fullScreenNone))
        #expect(on.contains(.canJoinAllSpaces))
    }

    @Test func overlayOffKeepsTheHUDOutOfFullScreenSpaces() {
        let off = OverlaySpacePolicy.collectionBehavior(showInFullscreen: false)
        #expect(off.contains(.fullScreenNone))
        #expect(!off.contains(.fullScreenAuxiliary))
        // The ordinary desktop Spaces are unaffected either way.
        #expect(off.contains(.canJoinAllSpaces))
    }
}

/// Sampling is driven by what the user can actually see. Each scope names the
/// visible surfaces; each metric names the one status item metric that may be
/// read. The union of those two is the only work allowed in a tick.
struct SamplingScopeTests {
    private func demand(columns: Bool, metric: StatusBarMetric) -> SamplingDemand {
        SamplingDemand(
            computeColumn: columns,
            memoryColumn: columns,
            storageColumn: columns,
            networkColumn: columns,
            statusBarMetric: metric
        )
    }

    @Test func visibleSurfacesResolveToTheirScope() {
        #expect(SamplingScope.resolve(hudVisible: true, statusBarVisible: true) == .full)
        #expect(SamplingScope.resolve(hudVisible: true, statusBarVisible: false) == .hudOnly)
        #expect(SamplingScope.resolve(hudVisible: false, statusBarVisible: true) == .statusBarOnly)
        #expect(SamplingScope.resolve(hudVisible: false, statusBarVisible: false) == .none)
    }

    @Test func hudAndMenuBarSampleEverythingTheColumnsAskFor() {
        let f = Sampler.Flags.forTick(
            scope: .full,
            demand: demand(columns: true, metric: .cpu)
        )
        #expect(f.collectGPU)
        #expect(f.collectCPU)
        #expect(f.collectMemory)
        #expect(f.collectPower)
        #expect(f.collectStorage)
        #expect(f.collectNetwork)
        #expect(f.collectThermal)
        #expect(!f.isEmpty)
    }

    @Test func hiddenHUDReadsOnlyTheMenuBarMetric() {
        for metric in StatusBarMetric.allCases {
            let f = Sampler.Flags.forTick(
                scope: .statusBarOnly,
                demand: demand(columns: true, metric: metric)
            )
            let expected: (gpu: Bool, cpu: Bool, pwr: Bool, mem: Bool, net: Bool) = switch metric {
            case .gpu: (true, false, false, false, false)
            case .cpu: (false, true, false, false, false)
            case .pwr: (false, false, true, false, false)
            case .memory: (false, false, false, true, false)
            case .pressure: (false, false, false, true, false)
            case .network: (false, false, false, false, true)
            case .icon: (false, false, false, false, false)
            }
            #expect(f.collectGPU == expected.gpu)
            #expect(f.collectCPU == expected.cpu)
            #expect(f.collectPower == expected.pwr)
            #expect(f.collectMemory == expected.mem)
            #expect(f.collectNetwork == expected.net)
            // Nothing only the HUD columns read survives.
            #expect(!f.collectStorage)
            #expect(!f.collectThermal)
            #expect(f.isEmpty == (metric == .icon))
        }
    }

    @Test func hiddenMenuBarStopsTheStatusBarMetricEvenWhenTheHUDIsVisible() {
        let f = Sampler.Flags.forTick(
            scope: .hudOnly,
            demand: demand(columns: false, metric: .cpu)
        )
        #expect(f.isEmpty)

        let columns = Sampler.Flags.forTick(
            scope: .hudOnly,
            demand: demand(columns: true, metric: .cpu)
        )
        #expect(columns.collectStorage)
        #expect(columns.collectNetwork)
        #expect(columns.collectThermal)
        // CPU was already demanded by the compute column, not by the bar.
        #expect(columns.collectCPU)
    }

    @Test func iconOnlyWithHiddenHUDPausesEverything() {
        let f = Sampler.Flags.forTick(
            scope: .statusBarOnly,
            demand: demand(columns: true, metric: .icon)
        )
        #expect(f.isEmpty)
    }

    @Test func noVisibleSurfaceProducesNoWork() {
        let f = Sampler.Flags.forTick(
            scope: .none,
            demand: demand(columns: true, metric: .cpu)
        )
        #expect(f.isEmpty)
    }

    @Test func pressureAndNetworkSelectTheirSampler() {
        let pressure = Sampler.Flags.forTick(
            scope: .statusBarOnly,
            demand: demand(columns: false, metric: .pressure)
        )
        #expect(pressure.collectMemory)
        #expect(!pressure.collectCPU)
        #expect(!pressure.collectNetwork)

        let network = Sampler.Flags.forTick(
            scope: .statusBarOnly,
            demand: demand(columns: false, metric: .network)
        )
        #expect(network.collectNetwork)
        #expect(!network.collectMemory)
        #expect(!network.collectCPU)
    }

    @Test func menuBarMetricIsReadEvenWhenItsColumnIsHidden() {
        let f = Sampler.Flags.forTick(
            scope: .full,
            demand: demand(columns: false, metric: .memory)
        )
        #expect(f.collectMemory)
        #expect(!f.collectCPU)
        #expect(!f.collectGPU)
        #expect(!f.collectPower)
        #expect(!f.collectStorage)
        #expect(!f.collectNetwork)
        #expect(!f.collectThermal)
    }
}
