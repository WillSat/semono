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

/// The sampling scope is what keeps a hidden HUD from costing anything: with
/// the HUD off screen, only the menu bar metric is read.
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

    @Test func awakeSamplesEverythingTheColumnsAskFor() {
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
    }

    @Test func sleepingSamplesOnlyTheMenuBarMetric() {
        for metric in StatusBarMetric.allCases {
            let f = Sampler.Flags.forTick(
                scope: .statusBarOnly,
                demand: demand(columns: true, metric: metric)
            )
            let expected: (gpu: Bool, cpu: Bool, pwr: Bool, mem: Bool) = switch metric {
            case .gpu: (true, false, false, false)
            case .cpu: (false, true, false, false)
            case .pwr: (false, false, true, false)
            case .memory: (false, false, false, true)
            }
            #expect(f.collectGPU == expected.gpu)
            #expect(f.collectCPU == expected.cpu)
            #expect(f.collectPower == expected.pwr)
            #expect(f.collectMemory == expected.mem)
            // Nothing only the HUD columns read survives.
            #expect(!f.collectStorage)
            #expect(!f.collectNetwork)
            #expect(!f.collectThermal)
        }
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
