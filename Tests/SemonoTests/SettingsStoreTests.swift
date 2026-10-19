import Combine
import Testing
@testable import Semono

struct SettingsStoreTests {
    @Test @MainActor func currentSettingsAreTheDefaults() {
        #expect(SettingsStore.Defaults.refreshInterval == 4)
        #expect(SettingsStore.Defaults.backgroundOpacity == 0.9)
        #expect(SettingsStore.Defaults.hudCorner == HUDPosition.bottomRight.rawValue)
        #expect(SettingsStore.Defaults.hudTheme == HUDTheme.light.rawValue)
        #expect(SettingsStore.Defaults.showInFullscreen == false)
        #expect(SettingsStore.Defaults.statusBarMetric == StatusBarMetric.memory.rawValue)
        #expect(SettingsStore.Defaults.showComputeColumn)
        #expect(SettingsStore.Defaults.showMemoryColumn)
        #expect(!SettingsStore.Defaults.showStorageColumn)
        #expect(SettingsStore.Defaults.showNetworkColumn)
        #expect(SettingsStore.Defaults.launchAtLogin)
        #expect(SettingsStore.Defaults.showHUD)
        #expect(SettingsStore.Defaults.autoUpdateCheck)
    }

    @Test func refreshOptionsAreOrdered() {
        #expect(SettingsStore.refreshOptions == [1, 2, 3, 4, 5, 10])
        #expect(SettingsStore.customRefreshTag == 0)
    }

    @Test func customRefreshSecondsClampAndRound() {
        #expect(SettingsStore.clampedRefreshSeconds(0.05) == 0.10)
        #expect(SettingsStore.clampedRefreshSeconds(0.104) == 0.10)
        #expect(SettingsStore.clampedRefreshSeconds(1.234) == 1.23)
        #expect(SettingsStore.clampedRefreshSeconds(100.01) == 100.00)
        #expect(SettingsStore.clampedRefreshSeconds(.nan) == SettingsStore.Defaults.refreshCustomSeconds)
    }

    @Test @MainActor func effectiveRefreshUsesPresetOrCustom() {
        let store = SettingsStore.shared
        let oldPreset = store.refreshInterval
        let oldCustom = store.refreshCustomSeconds
        defer {
            store.refreshInterval = oldPreset
            store.refreshCustomSeconds = oldCustom
        }

        store.refreshInterval = 10
        #expect(store.effectiveRefreshInterval == 10)

        store.refreshInterval = SettingsStore.customRefreshTag
        store.refreshCustomSeconds = 0.5
        #expect(store.effectiveRefreshInterval == 0.5)

        store.refreshCustomSeconds = 0.05
        #expect(store.effectiveRefreshInterval == 0.10)
    }

    @Test func hudThemesAreDarkAndLight() {
        #expect(HUDTheme.allCases.map(\.rawValue) == ["dark", "light"])
    }

    @Test @MainActor func defaultsChangePublishesObjectWillChange() async {
        let store = SettingsStore.shared
        let original = store.showComputeColumn
        var changed = false
        let cancellable = store.objectWillChange.sink { changed = true }
        defer {
            store.showComputeColumn = original
            cancellable.cancel()
        }

        store.showComputeColumn = !original
        try? await Task.sleep(for: .milliseconds(150))
        #expect(changed)
    }
}
