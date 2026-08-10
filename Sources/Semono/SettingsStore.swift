import SwiftUI
import ServiceManagement

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("refreshInterval") var refreshInterval = 3
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("backgroundOpacity") var backgroundOpacity = 0.6
    @AppStorage("hudX") var hudX: Double = -1
    @AppStorage("hudY") var hudY: Double = -1
    @AppStorage("hudWidth") var hudWidth: Double = -1
    @AppStorage("hudHeight") var hudHeight: Double = -1
    @AppStorage("hudHasSavedPosition") var hudHasSavedPosition = false
    @AppStorage("showInFullscreen") var showInFullscreen = true
    @AppStorage("fontName") var fontName = "DepartureMono-Regular"
    @AppStorage("fontScale") var fontScale: Double = 0
    @AppStorage("statusBarMetric") var statusBarMetric = "cpu"
    @AppStorage("showComputeColumn") var showComputeColumn = true
    @AppStorage("showMemoryColumn") var showMemoryColumn = true
    @AppStorage("showStorageColumn") var showStorageColumn = true
    @AppStorage("showNetworkColumn") var showNetworkColumn = true
    @AppStorage("useBlockDisplay") var useBlockDisplay = false
    @AppStorage("appLanguage") var appLanguage = LocaleManager.detectSystemLanguage()

    static let availableFonts: [(name: String, label: String)] = {
        var fonts: [(String, String)] = [("DepartureMono-Regular", "Departure Mono")]

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
    }()

    func resetToDefaults() {
        if launchAtLogin {
            try? SMAppService.mainApp.unregister()
        }
        refreshInterval = 3
        launchAtLogin = false
        backgroundOpacity = 0.6
        hudX = -1
        hudY = -1
        hudWidth = -1
        hudHeight = -1
        hudHasSavedPosition = false
        showInFullscreen = true
        fontName = "DepartureMono-Regular"
        fontScale = 0
        statusBarMetric = "cpu"
        showComputeColumn = true
        showMemoryColumn = true
        showStorageColumn = true
        showNetworkColumn = true
        useBlockDisplay = false
        appLanguage = LocaleManager.detectSystemLanguage()
    }
}
