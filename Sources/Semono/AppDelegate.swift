import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?
    private var hudWindowDelegate: WindowDelegate?
    private var settingsWindow: NSWindow?
    private var settingsWindowDelegate: WindowDelegate?
    private var statusItem: NSStatusItem?
    private let metrics = MetricsCollector()
    private var saveFrameTimer: Timer?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        registerFont()
        setupStatusBar()
        showHUD()
        metrics.start()
        syncLoginItemState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        metrics.stop()
    }

    @objc private func screenParamsChanged() {
        reposition()
    }

    private func syncLoginItemState() {
        SettingsStore.shared.launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Window

    private func showHUD() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = hudFrame(for: screen)

        let w = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        w.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        if SettingsStore.shared.showInFullscreen {
            w.collectionBehavior.insert(.fullScreenAuxiliary)
        } else {
            w.collectionBehavior.insert(.fullScreenNone)
        }
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: HUDView(metrics: metrics))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = hosting

        let delegate = WindowDelegate(
            onMove: { [weak self, weak w] in self?.scheduleSaveFrame(w) },
            onResize: { [weak self, weak w] in self?.scheduleSaveFrame(w) }
        )
        hudWindowDelegate = delegate
        w.delegate = delegate

        w.makeKeyAndOrderFront(nil)
        window = w

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self, weak w] in
            self?.scheduleSaveFrame(w)
        }
    }

    private func reposition() {
        let screen = window?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = hudFrame(for: screen)
        window?.setFrame(frame, display: true, animate: false)
    }

    private func scheduleSaveFrame(_ w: NSWindow?) {
        saveFrameTimer?.invalidate()
        saveFrameTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self, weak w] _ in
            guard let self, let w else { return }
            Task { @MainActor in self.saveFrame(w) }
        }
    }

    private func saveFrame(_ w: NSWindow?) {
        guard let w else { return }
        let f = w.frame
        SettingsStore.shared.hudX = f.origin.x
        SettingsStore.shared.hudY = f.origin.y
        SettingsStore.shared.hudWidth = f.size.width
        SettingsStore.shared.hudHeight = f.size.height
    }

    private func hudFrame(for screen: NSScreen) -> NSRect {
        let x = SettingsStore.shared.hudX
        let y = SettingsStore.shared.hudY
        let w = SettingsStore.shared.hudWidth
        let h = SettingsStore.shared.hudHeight
        if x >= 0, y >= 0, w > 0, h > 0 {
            return NSRect(x: x, y: y, width: w, height: h)
        }
        return DockDetector.defaultFrame(for: screen)
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.33percent",
            accessibilityDescription: "Semono"
        )
        button.image?.isTemplate = true

        let menu = NSMenu()

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit Semono",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openSettings() {
        syncLoginItemState()
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Semono Settings"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: SettingsView(restartAction: { [weak self] in
            self?.restartApp()
        }))
        w.center()
        w.makeKeyAndOrderFront(nil)
        settingsWindow = w

        let delegate = WindowDelegate(onClose: { [weak self] in
            self?.settingsWindow = nil
            self?.settingsWindowDelegate = nil
        })
        settingsWindowDelegate = delegate
        w.delegate = delegate
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func restartApp() {
        let appURL = Bundle.main.bundleURL
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.3; open '\(appURL.path)'"]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Font

    private func registerFont() {
        guard let url = Bundle.main.url(forResource: "DepartureMono-Regular", withExtension: "otf") else {
            return
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

// MARK: - Window Delegate

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onClose: (() -> Void)?
    let onMove: (() -> Void)?
    let onResize: (() -> Void)?

    init(
        onClose: (() -> Void)? = nil,
        onMove: (() -> Void)? = nil,
        onResize: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        self.onMove = onMove
        self.onResize = onResize
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
    func windowDidMove(_ notification: Notification) { onMove?() }
    func windowDidResize(_ notification: Notification) { onResize?() }
}
