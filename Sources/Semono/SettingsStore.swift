import SwiftUI
import ServiceManagement
import AppKit

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    /// Single source for default values. The `@AppStorage` declarations and
    /// `resetToDefaults` both reference these, so the two lists cannot drift.
    enum Defaults {
        static let refreshInterval = 3
        static let launchAtLogin = false
        static let backgroundOpacity = 0.6
        static let hudX: Double = -1
        static let hudY: Double = -1
        static let hudWidth: Double = -1
        static let hudHeight: Double = -1
        static let hudHasSavedPosition = false
        static let showInFullscreen = true
        static let fontName = "DepartureMono-Regular"
        static let fontScale: Double = 0
        static let statusBarMetric = StatusBarMetric.cpu.rawValue
        static let showComputeColumn = true
        static let showMemoryColumn = true
        static let showStorageColumn = true
        static let showNetworkColumn = true
        static let useBlockDisplay = false
        static let appLanguage = LocaleManager.detectSystemLanguage()
    }

    /// Refresh tiers offered by the pickers.
    static let refreshOptions = [1, 2, 3, 5]

    @AppStorage("refreshInterval") var refreshInterval = Defaults.refreshInterval
    @AppStorage("launchAtLogin") var launchAtLogin = Defaults.launchAtLogin
    @AppStorage("backgroundOpacity") var backgroundOpacity = Defaults.backgroundOpacity
    @AppStorage("hudX") var hudX = Defaults.hudX
    @AppStorage("hudY") var hudY = Defaults.hudY
    @AppStorage("hudWidth") var hudWidth = Defaults.hudWidth
    @AppStorage("hudHeight") var hudHeight = Defaults.hudHeight
    @AppStorage("hudHasSavedPosition") var hudHasSavedPosition = Defaults.hudHasSavedPosition
    @AppStorage("showInFullscreen") var showInFullscreen = Defaults.showInFullscreen
    @AppStorage("fontName") var fontName = Defaults.fontName
    @AppStorage("fontScale") var fontScale = Defaults.fontScale
    @AppStorage("statusBarMetric") var statusBarMetric = Defaults.statusBarMetric
    @AppStorage("showComputeColumn") var showComputeColumn = Defaults.showComputeColumn
    @AppStorage("showMemoryColumn") var showMemoryColumn = Defaults.showMemoryColumn
    @AppStorage("showStorageColumn") var showStorageColumn = Defaults.showStorageColumn
    @AppStorage("showNetworkColumn") var showNetworkColumn = Defaults.showNetworkColumn
    @AppStorage("useBlockDisplay") var useBlockDisplay = Defaults.useBlockDisplay
    @AppStorage("appLanguage") var appLanguage = Defaults.appLanguage

    /// Fixed-pitch fonts available for the HUD. Starts with the bundled
    /// Departure Mono; `loadAvailableFontsIfNeeded` fills in the system's
    /// fixed-pitch families off the main thread (the enumeration constructs
    /// an NSFont per candidate and can take hundreds of milliseconds).
    @Published private(set) var availableFonts: [(name: String, label: String)] = [
        (Defaults.fontName, "Departure Mono")
    ]

    @MainActor
    func loadAvailableFontsIfNeeded() {
        guard availableFonts.count <= 1 else { return }
        let bundled = (name: Defaults.fontName, label: "Departure Mono")
        Task.detached(priority: .userInitiated) {
            let fonts = Self.loadAvailableFonts(bundled: bundled)
            await MainActor.run {
                SettingsStore.shared.availableFonts = fonts
            }
        }
    }

    /// Enumerates the system's fixed-pitch fonts. Not actor-isolated so it
    /// can run off the main thread.
    nonisolated static func loadAvailableFonts(bundled: (name: String, label: String)) -> [(name: String, label: String)] {
        var fonts: [(String, String)] = [bundled]

        for family in NSFontManager.shared.availableFontFamilies.sorted() {
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else { continue }
            for m in members {
                // Members are [PostScriptName, familyName, traits, weight]; the
                // traits mask is not checked because `isFixedPitch` already
                // covers the intent (a trait test like `== 5` would wrongly
                // admit only the bold-italic member of each family).
                guard let psName = m[0] as? String,
                      let font = NSFont(name: psName, size: 11),
                      font.isFixedPitch
                else { continue }
                fonts.append((psName, family))
                break
            }
        }
        return fonts
    }

    func resetToDefaults() {
        if launchAtLogin {
            try? SMAppService.mainApp.unregister()
        }
        refreshInterval = Defaults.refreshInterval
        launchAtLogin = Defaults.launchAtLogin
        backgroundOpacity = Defaults.backgroundOpacity
        hudX = Defaults.hudX
        hudY = Defaults.hudY
        hudWidth = Defaults.hudWidth
        hudHeight = Defaults.hudHeight
        hudHasSavedPosition = Defaults.hudHasSavedPosition
        showInFullscreen = Defaults.showInFullscreen
        fontName = Defaults.fontName
        fontScale = Defaults.fontScale
        statusBarMetric = Defaults.statusBarMetric
        showComputeColumn = Defaults.showComputeColumn
        showMemoryColumn = Defaults.showMemoryColumn
        showStorageColumn = Defaults.showStorageColumn
        showNetworkColumn = Defaults.showNetworkColumn
        useBlockDisplay = Defaults.useBlockDisplay
        appLanguage = Defaults.appLanguage
    }
}
