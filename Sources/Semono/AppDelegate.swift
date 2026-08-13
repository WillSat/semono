import AppKit
import SwiftUI
import ServiceManagement
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?
    private var hudWindowDelegate: WindowDelegate?
    private var statusItem: NSStatusItem?
    private var menubarView: MenubarContentView?
    let metrics = MetricsCollector()
    private var saveFrameTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Debounce for persisting the HUD frame after drag/resize ends.
    private static let frameSaveDebounce: TimeInterval = 0.5
    /// Delay before the first frame save so the initial auto-size settles.
    private static let initialFrameSaveDelay: TimeInterval = 0.1
    /// Minimum status bar item width so the readout stays comfortably clickable.
    private static let statusBarMinWidth: CGFloat = 28

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        pruneLegacyDefaults()
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

        #if DEBUG
        // Screenshot-automation hook: opens both windows, then quits. Debug
        // builds only, so it can never leak into a shipped bundle.
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
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        metrics.stop()
    }

    @objc private func screenParamsChanged() {
        reposition()
    }

    /// Removes preference keys left behind by features that no longer exist
    /// (adaptive sleep, pre-1.5 window keys), so the preferences file stays
    /// tidy across upgrades.
    private func pruneLegacyDefaults() {
        let legacyKeys = [
            "adaptiveSleep", "sleepSensitivity", "sleepHysteresis", "sleepInterval",
            "hideInFullscreen", "hudPosition",
        ]
        for key in legacyKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// SMAppService.mainApp.status is an XPC round-trip; resolve it off the
    /// main thread and publish the result back.
    private func syncLoginItemState() {
        Task.detached(priority: .utility) {
            let enabled = SMAppService.mainApp.status == .enabled
            await MainActor.run {
                SettingsStore.shared.launchAtLogin = enabled
            }
        }
    }

    private func observeMetrics() {
        Publishers.Merge(
            metrics.$gpuUsage.map { _ in },
            metrics.$cpuUsage.map { _ in }
        )
        .merge(with: metrics.$memoryUsage.map { _ in })
        .merge(with: metrics.$powerUsage.map { _ in })
        .merge(with: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in })
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateStatusBarTitle() }
        .store(in: &cancellables)
    }

    // MARK: - Fullscreen behavior sync

    /// Reacts to settings changes after they are written. `objectWillChange`
    /// fires *before* the write, so a sink reading the property there still
    /// sees the old value; the post-write `didChangeNotification` (the same
    /// mechanism LocaleManager relies on) avoids that off-by-one-event lag.
    private var appliedFullscreenBehavior: Bool?

    private func observeSettings() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.syncFullscreenBehavior() }
            .store(in: &cancellables)
    }

    private func syncFullscreenBehavior() {
        let enabled = SettingsStore.shared.showInFullscreen
        guard appliedFullscreenBehavior != enabled else { return }
        applyFullscreenBehavior(enabled)
    }

    private func applyFullscreenBehavior(_ enabled: Bool) {
        appliedFullscreenBehavior = enabled
        guard let w = window else { return }
        w.collectionBehavior.remove(.fullScreenAuxiliary)
        w.collectionBehavior.remove(.fullScreenNone)
        w.collectionBehavior.insert(enabled ? .fullScreenAuxiliary : .fullScreenNone)
    }

    // MARK: - HUD Window

    /// The screen the user is most likely looking at: the one hosting the
    /// key window, else the one under the pointer, else the first screen.
    private var preferredScreen: NSScreen? {
        if let keyScreen = NSApp.keyWindow?.screen { return keyScreen }
        let mouse = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return mouseScreen
        }
        return NSScreen.screens.first
    }

    private func showHUD() {
        guard let screen = preferredScreen else { return }
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
        w.animationBehavior = .none
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

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialFrameSaveDelay) { [weak self, weak w] in
            self?.scheduleSaveFrame(w)
        }
    }

    private func reposition() {
        guard let w = window else { return }
        let screen = w.screen ?? preferredScreen
        guard let screen else { return }
        w.setFrame(hudFrame(for: screen), display: true, animate: false)
    }

    private func scheduleSaveFrame(_ w: NSWindow?) {
        saveFrameTimer?.invalidate()
        saveFrameTimer = Timer.scheduledTimer(withTimeInterval: Self.frameSaveDebounce, repeats: false) { [weak self, weak w] _ in
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
        let defaults = SettingsStore.Defaults.self
        let hasSaved = store.hudHasSavedPosition
            || (store.hudX != defaults.hudX && store.hudY != defaults.hudY)
        guard hasSaved, store.hudWidth > 0, store.hudHeight > 0 else {
            return HUDFrame.defaultFrame(for: screen)
        }
        let frame = NSRect(x: store.hudX, y: store.hudY, width: store.hudWidth, height: store.hudHeight)
        guard NSScreen.screens.contains(where: { $0.frame.intersects(frame) }) else {
            return HUDFrame.defaultFrame(for: screen)
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
        let metric = StatusBarMetric(rawValue: SettingsStore.shared.statusBarMetric) ?? .cpu
        let text = metric.text(from: metrics)
        let type = metric.label
        guard let view = menubarView,
              text != view.displayText || type != view.displayType
        else { return }
        view.displayText = text
        view.displayType = type
        let width = max(Self.statusBarMinWidth, view.fittingWidth)
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
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !registered {
            // The HUD falls back to the monospaced system font; log the
            // failure instead of letting it pass silently.
            Logger(subsystem: "com.semono.app", category: "font")
                .error("Departure Mono registration failed: \(String(describing: error?.takeRetainedValue().localizedDescription), privacy: .public)")
        }
    }
}

// MARK: - Window Delegate

private final class WindowDelegate: NSObject, NSWindowDelegate {
    let onMove: (() -> Void)?
    let onResize: (() -> Void)?

    init(
        onMove: (() -> Void)? = nil,
        onResize: (() -> Void)? = nil
    ) {
        self.onMove = onMove
        self.onResize = onResize
    }

    func windowDidMove(_ notification: Notification) { onMove?() }
    func windowDidResize(_ notification: Notification) { onResize?() }
}
