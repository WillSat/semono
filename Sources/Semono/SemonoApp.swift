import AppKit
import SwiftUI

/// Routes the settings-window request from the AppKit menu bar into the
/// SwiftUI scene system.
@MainActor
enum WindowRouter {
    static var openSettings: (() -> Void)?

    static func register(openWindow: OpenWindowAction) {
        openSettings = { openWindow(id: "settings") }
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
                .frame(minWidth: 560, minHeight: 400)
        }
        .defaultSize(width: 660, height: 460)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)
    }
}
