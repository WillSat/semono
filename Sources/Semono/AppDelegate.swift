import AppKit
import SwiftUI
import ServiceManagement
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?
    private var hudWindowDelegate: WindowDelegate?
    private var statusItem: NSStatusItem?
    private var menubarView: MenubarContentView?
    let metrics = MetricsCollector()
    private var saveFrameTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerFont()
        setupStatusBar()
        showHUD()
        metrics.start()
        syncLoginItemState()
        observeMetrics()
        observeSettings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if CommandLine.arguments.contains("--open-windows") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.activate()
                WindowRouter.openMonitor?()
                WindowRouter.openSettings?()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                NSApp.terminate(nil)
            }
        }
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

    private func observeMetrics() {
        Publishers.Merge(
            metrics.$gpuUsage.map { _ in },
            metrics.$cpuUsage.map { _ in }
        )
        .merge(with: metrics.$memoryUsage.map { _ in })
        .merge(with: metrics.$powerUsage.map { _ in })
        .merge(with: metrics.$isSleeping.map { _ in })
        .merge(with: SettingsStore.shared.objectWillChange)
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateStatusBarTitle() }
        .store(in: &cancellables)
    }

    private func observeSettings() {
        var lastFullscreen = SettingsStore.shared.showInFullscreen
        SettingsStore.shared.objectWillChange
            .sink { [weak self] _ in
                let now = SettingsStore.shared.showInFullscreen
                guard now != lastFullscreen else { return }
                lastFullscreen = now
                self?.applyFullscreenBehavior(now)
            }
            .store(in: &cancellables)
    }

    private func applyFullscreenBehavior(_ enabled: Bool) {
        guard let w = window else { return }
        w.collectionBehavior.remove(.fullScreenAuxiliary)
        w.collectionBehavior.remove(.fullScreenNone)
        w.collectionBehavior.insert(enabled ? .fullScreenAuxiliary : .fullScreenNone)
    }

    // MARK: - HUD Window

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
        applyFullscreenBehavior(SettingsStore.shared.showInFullscreen)
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: HUDView(metrics: metrics) { [weak self] in
            self?.openDetail()
        })
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
        guard let w = window else { return }
        let screen = w.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        w.setFrame(hudFrame(for: screen), display: true, animate: false)
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
        SettingsStore.shared.hudHasSavedPosition = true
    }

    /// Restores the saved frame as-is (no position clamping — the HUD may be
    /// tucked anywhere), or the default corner on first launch or when the
    /// saved frame's screen is gone.
    private func hudFrame(for screen: NSScreen) -> NSRect {
        let store = SettingsStore.shared
        let hasSaved = store.hudHasSavedPosition || (store.hudX != -1 && store.hudY != -1)
        guard hasSaved, store.hudWidth > 0, store.hudHeight > 0 else {
            return DockDetector.defaultFrame(for: screen)
        }
        let frame = NSRect(x: store.hudX, y: store.hudY, width: store.hudWidth, height: store.hudHeight)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else {
            return DockDetector.defaultFrame(for: screen)
        }
        return frame
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let view = MenubarContentView()

        let menu = NSMenu()
        let settingsItem = NSMenuItem(
            title: LocaleManager.shared.localized("Settings..."),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: LocaleManager.shared.localized("Quit Semono"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        view.menu = menu

        statusItem?.view = view
        menubarView = view
    }

    private func updateStatusBarTitle() {
        let metric = SettingsStore.shared.statusBarMetric
        let text: String
        let type: String
        switch metric {
        case "memory":
            text = "\(Int(metrics.memoryUsage * 100))%"
            type = "MEM"
        case "gpu":
            text = "\(Int(metrics.gpuUsage * 100))%"
            type = "GPU"
        case "pwr":
            text = String(format: "%.1f", metrics.powerUsage)
            type = "PWR"
        default:
            text = "\(Int(metrics.cpuUsage * 100))%"
            type = "CPU"
        }
        guard let view = menubarView,
              text != view.displayText || type != view.displayType
                || metrics.isSleeping != view.isSleeping
        else { return }
        view.displayText = text
        view.displayType = type
        view.isSleeping = metrics.isSleeping
        let width = max(28, view.fittingWidth)
        if statusItem?.length != width {
            statusItem?.length = width
        }
    }

    // MARK: - Window Opening

    @objc private func openSettings() {
        NSApp.activate()
        syncLoginItemState()
        WindowRouter.openSettings?()
    }

    @objc private func openDetail() {
        NSApp.activate()
        WindowRouter.openMonitor?()
    }

    @objc private func quitApp() {
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
