import AppKit
import SwiftUI

enum SemonoWindow {
    case settings
    case deviceInfo
    case guide
    case about
}

/// Weak references to the SwiftUI scene windows. The NSViewRepresentable below
/// registers the window as soon as it is attached; overriding
/// `NSWindow.identifier` would interfere with SwiftUI's own scene bookkeeping.
@MainActor
enum WindowRegistry {
    static weak var settings: NSWindow?
    static weak var deviceInfo: NSWindow?
    static weak var guide: NSWindow?
    static weak var about: NSWindow?

    static var settingsWindow: NSWindow? { settings }
    static var deviceInfoWindow: NSWindow? { deviceInfo }
    static var guideWindow: NSWindow? { guide }
    static var aboutWindow: NSWindow? { about }
}

struct WindowRegistration: NSViewRepresentable {
    let window: SemonoWindow

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        register(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        register(nsView)
    }

    private func register(_ view: NSView) {
        DispatchQueue.main.async {
            switch window {
            case .settings: WindowRegistry.settings = view.window
            case .deviceInfo: WindowRegistry.deviceInfo = view.window
            case .guide: WindowRegistry.guide = view.window
            case .about: WindowRegistry.about = view.window
            }
        }
    }
}

/// Brings a SwiftUI scene window to the front from an LSUIElement app.
///
/// Activation alone does not raise a newly created window in an accessory app.
/// The window is ordered front regardless (so it cannot stay behind another
/// app's windows) and then made key. The window may not exist on the very
/// first open, hence the short retries.
@MainActor
enum WindowFronting {
    static func bringToFront(_ window: SemonoWindow) {
        NSApp.activate()
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
        if raise(window) { return }

        Task { @MainActor in
            for delay in [80, 160, 300, 500] {
                try? await Task.sleep(for: .milliseconds(delay))
                if raise(window) { return }
            }
        }
    }

    @discardableResult
    private static func raise(_ window: SemonoWindow) -> Bool {
        let registered: NSWindow?
        switch window {
        case .settings: registered = WindowRegistry.settingsWindow
        case .deviceInfo: registered = WindowRegistry.deviceInfoWindow
        case .guide: registered = WindowRegistry.guideWindow
        case .about: registered = WindowRegistry.aboutWindow
        }
        let target = registered ?? NSApp.windows.first { candidate in
            titles(for: window).contains(candidate.title)
        }
        guard let target else { return false }
        target.orderFrontRegardless()
        target.makeKeyAndOrderFront(nil)
        return true
    }

    /// Fallback when the registration view has not attached yet. The window
    /// title is set by the scene's navigation title.
    private static func titles(for window: SemonoWindow) -> [String] {
        switch window {
        case .settings: ["Semono Settings", "Semono 设置"]
        case .deviceInfo: ["Device Information", "设备信息"]
        case .guide:
            [LocaleManager.shared.localized("User Guide"), "User Guide", "使用说明"]
        case .about:
            [LocaleManager.shared.localized("About Semono"), "About Semono", "关于 Semono"]
        }
    }
}
