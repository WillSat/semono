import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @AppStorage("refreshInterval") var refreshInterval = 2
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("backgroundOpacity") var backgroundOpacity = 0.6
    @AppStorage("hudX") var hudX: Double = -1
    @AppStorage("hudY") var hudY: Double = -1
    @AppStorage("hudWidth") var hudWidth: Double = -1
    @AppStorage("hudHeight") var hudHeight: Double = -1
    @AppStorage("showInFullscreen") var showInFullscreen = true
    @AppStorage("fontName") var fontName = "DepartureMono-Regular"
    @AppStorage("statusBarMetric") var statusBarMetric = "cpu"

    static let availableFonts: [(name: String, label: String)] = {
        var fonts: [(String, String)] = [("DepartureMono-Regular", "Departure Mono")]

        for family in NSFontManager.shared.availableFontFamilies.sorted() {
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family) else { continue }
            for m in members {
                guard let psName = m[0] as? String,
                      let font = NSFont(name: psName, size: 11),
                      font.isFixedPitch,
                      m[2] as? Int == 5  // regular weight only
                else { continue }
                fonts.append((psName, family))
                break
            }
        }
        return fonts
    }()
}
