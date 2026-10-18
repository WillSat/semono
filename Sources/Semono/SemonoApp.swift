import AppKit
import SwiftUI

/// Routes window requests from the AppKit menu bar into the SwiftUI scene
/// system.
@MainActor
enum WindowRouter {
    static var openSettings: (() -> Void)?
    static var openDeviceInfo: (() -> Void)?

    static func register(openWindow: OpenWindowAction) {
        openSettings = {
            openWindow(id: "settings")
            WindowFronting.bringToFront(.settings)
        }
        openDeviceInfo = {
            openWindow(id: "device-info")
            WindowFronting.bringToFront(.deviceInfo)
        }
    }
}

/// Native SwiftUI scene for the settings window: macOS 26/27 chrome, a native
/// toolbar, and the System Settings look.
///
/// Note: the `Settings` scene doesn't present for LSUIElement (menu-bar-only)
/// apps, so settings is a regular `Window` scene.
@main
struct SemonoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // `body` can be re-evaluated; registration just rewrites the same
        // closure, so the repeat is harmless.
        let _ = WindowRouter.register(openWindow: openWindow)

        Window("Semono Settings", id: "settings") {
            SettingsView()
        }
        .defaultSize(width: 900, height: 640)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

        Window("Device Information", id: "device-info") {
            DeviceInfoView()
        }
        .defaultSize(width: 1080, height: 720)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}
