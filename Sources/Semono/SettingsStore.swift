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
}
