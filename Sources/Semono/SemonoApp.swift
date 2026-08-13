import AppKit
import SwiftUI

/// Routes window-open requests from the AppKit menu bar / HUD into the
/// SwiftUI scene system.
@MainActor
enum WindowRouter {
    static var openMonitor: (() -> Void)?
    static var openSettings: (() -> Void)?

    static func register(openWindow: OpenWindowAction) {
        openMonitor = { openWindow(id: "monitor") }
        openSettings = { openWindow(id: "settings") }
    }
}

/// Native SwiftUI scenes give the monitor and settings windows proper
/// macOS 26/27 chrome: Liquid Glass toolbars that blur scrolling content,
/// native scroll performance, and the System Settings look.
///
/// Note: the `Settings` scene doesn't present for LSUIElement (menu-bar-only)
/// apps, so settings is a regular `Window` scene like the monitor.
@main
struct SemonoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // `body` can be re-evaluated; registration just rewrites the same two
        // closures, so the repeat is harmless. (An `if` guard would need
        // SceneBuilder's buildOptional, which it does not provide.)
        let _ = WindowRouter.register(openWindow: openWindow)

        Window("Semono Monitor", id: "monitor") {
            DetailView(metrics: appDelegate.metrics)
                .frame(minWidth: 640, minHeight: 480)
        }
        .defaultSize(width: 860, height: 560)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(.suppressed)

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
