import AppKit
import SwiftUI
import ServiceManagement
import Combine
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var window: NSWindow?
    private var hudWindowDelegate: WindowDelegate?
    private var statusItem: NSStatusItem?
    private var menubarView: MenubarContentView?
    let metrics = MetricsCollector()
    private var saveSizeTimer: Timer?
    private var reanchorTimer: Timer?
    /// Guards the resize -> re-anchor -> resize cycle while SwiftUI lays the
    /// HUD out for a new set of columns or font scale.
    private var isRepositioning = false
    private var cancellables = Set<AnyCancellable>()
    private var wakeObservers: [NSObjectProtocol] = []
    /// Checkable "Show HUD" item, kept in sync with the persisted setting.
    private var hudMenuItem: NSMenuItem?
    private var infoMenuItem: NSMenuItem?
    private var guideMenuItem: NSMenuItem?
    private var updateMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var aboutMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?
    /// The menu bar can disappear while the process keeps running (full-screen
    /// Spaces). A light visibility probe is what lets sampling stop then, and
    /// start again when the bar is revealed.
    private var statusBarVisibilityTimer: Timer?
    private var lastStatusBarVisible: Bool?
    /// Snapshots used to wake the sampling loop only when a setting that
    /// actually changes demand was written.
    private var lastDemand: SamplingDemand?
    private var lastShowHUD: Bool?
    private var lastHUDCorner: String?
    private var lastHUDHorizontalMargin: Double?
    private var lastHUDVerticalMargin: Double?

    /// Debounce for persisting the HUD size after auto-resize ends.
    private static let sizeSaveDebounce: TimeInterval = 0.5
    /// Delay before the first size save/re-anchor so the initial auto-size
    /// settles.
    private static let initialFrameSaveDelay: TimeInterval = 0.1
    /// Minimum status bar item width so the readout stays comfortably clickable.
    private static let statusBarMinWidth: CGFloat = 28
    private static let firstRunGuideKey = "hasShownFirstRunGuide"

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        #if DEBUG
        // Screenshot/behaviour hooks for development builds only.
        if let raw = ProcessInfo.processInfo.environment["SEMONO_STATUS_BAR_METRIC"],
           StatusBarMetric(rawValue: raw) != nil {
            SettingsStore.shared.statusBarMetric = raw
        }
        if let raw = ProcessInfo.processInfo.environment["SEMONO_SHOW_HUD"] {
            SettingsStore.shared.showHUD = raw != "0"
        }
        #endif

        pruneLegacyDefaults()
        registerFont()
        setupStatusBar()
        // Registering the Space observers first means the HUD's own state is
        // translated into a sampling scope from the moment the window exists.
        startSpaceObservation()
        showHUD()
        metrics.start()
        startStatusBarVisibilityMonitoring()
        startWakeObservation()
        syncLoginItemState()
        lastDemand = SamplingDemand.current()
        lastShowHUD = SettingsStore.shared.showHUD
        lastHUDCorner = SettingsStore.shared.hudCorner
        lastHUDHorizontalMargin = SettingsStore.shared.hudMarginHorizontal
        lastHUDVerticalMargin = SettingsStore.shared.hudMarginVertical
        showFirstRunGuideIfNeeded()
        observeMetrics()
        observeSettings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        #if DEBUG
        // Screenshot-automation hooks. Debug builds only, so they can never
        // leak into a shipped bundle.
        if CommandLine.arguments.contains("--open-windows") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.activate()
                WindowRouter.openSettings?()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--open-device-info") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApp.activate()
                WindowRouter.openDeviceInfo?()
            }
        }
        if CommandLine.arguments.contains("--open-guide") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApp.activate()
                WindowRouter.openGuide?()
            }
        }
        if CommandLine.arguments.contains("--open-about") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NSApp.activate()
                WindowRouter.openAbout?()
            }
        }

        if CommandLine.arguments.contains("--open-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let view = self.menubarView, let menu = view.menu else { return }
                NSApp.activate()
                menu.popUp(
                    positioning: nil,
                    at: NSPoint(x: 0, y: view.bounds.height + 5),
                    in: view
                )
            }
        }
        #endif
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        metrics.stop()
        stopSpaceObservation()
        stopWakeObservation()
        saveSizeTimer?.invalidate()
        saveSizeTimer = nil
        reanchorTimer?.invalidate()
        reanchorTimer = nil
        statusBarVisibilityTimer?.invalidate()
        statusBarVisibilityTimer = nil
    }

    @objc private func screenParamsChanged() {
        reposition()
        // Displays appearing or disappearing can move the HUD between Spaces.
        refreshOverlay()
    }

    /// Removes preference keys left behind by features that no longer exist
    /// (adaptive sleep, pre-1.5 window keys), so the preferences file stays
    /// tidy across upgrades.
    private func pruneLegacyDefaults() {
        let legacyKeys = [
            "adaptiveSleep", "sleepSensitivity", "sleepHysteresis", "sleepInterval",
            "hideInFullscreen",
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
        .merge(with: metrics.$memoryPressureLevel.map { _ in })
        .merge(with: metrics.$downloadSpeed.map { _ in })
        .merge(with: metrics.$uploadSpeed.map { _ in })
        .merge(with: metrics.$networkType.map { _ in })
        .merge(with: metrics.$wifiRSSI.map { _ in })
        .merge(with: NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in })
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateStatusBarTitle() }
        .store(in: &cancellables)
    }

    // MARK: - Full-screen Spaces

    /// The overlay's Space policy. macOS puts every full-screen app in a Space
    /// of its own, and the "show in fullscreen" setting decides whether the HUD
    /// is allowed there — see `OverlaySpacePolicy`, where the membership, and
    /// with it the visibility on any given desktop, is left to the window
    /// server. All this class does is install the membership and then observe
    /// its consequence: whether the HUD is on the Space the user is looking at.
    private var spaceObservers: [NSObjectProtocol] = []
    /// The setting last installed on the window, so unrelated defaults writes
    /// (window size saves, slider changes, …) cannot re-order the overlay.
    private var appliedShowInFullscreen: Bool?
    /// Re-reads the state once a membership swap has settled.
    private var membershipSettle: Task<Void, Never>?

    /// Watches the user moving between Spaces — that is what decides whether
    /// the HUD is on screen, and with it whether sampling runs at all.
    private func startSpaceObservation() {
        let workspace = NSWorkspace.shared.notificationCenter
        spaceObservers = [
            workspace.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshOverlay() }
            },
            workspace.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refreshOverlay() }
            },
        ]
        refreshOverlay()
    }

    /// Applies a pending setting change and re-reads the resulting state.
    ///
    /// Writes made by this process are announced (`UserDefaults` posts its
    /// change notification), which is how the Settings toggle takes effect at
    /// once. Writes made by *another* process — a `defaults write`, say, or a
    /// preferences sync — are not announced to this one, so the Space
    /// notifications re-read the setting as well; the membership is only
    /// touched when the value actually differs, so this costs a comparison.
    private func refreshOverlay() {
        syncOverlayMembership()
        applyHUDFrameIfChanged()
        updateOverlayState(refreshStatusBarVisibility: true)
    }

    private func stopSpaceObservation() {
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in spaceObservers { workspace.removeObserver(observer) }
        spaceObservers.removeAll()
        membershipSettle?.cancel()
        membershipSettle = nil
    }

    /// A sleep/wake or display-wake gap is not a valid measurement interval:
    /// counters may have wrapped or reset and the elapsed time is huge. Reset
    /// the rate baselines before the next tick instead of reporting a spike or
    /// a false zero. Rates themselves use a monotonic clock, so a manual clock
    /// change or NTP correction does not affect them.
    private func startWakeObservation() {
        let center = NSWorkspace.shared.notificationCenter
        wakeObservers = [
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.metrics.resetRateBaselinesSoon() }
            },
            center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.metrics.resetRateBaselinesSoon() }
            },
        ]
    }

    private func stopWakeObservation() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in wakeObservers { center.removeObserver(observer) }
        wakeObservers.removeAll()
    }

    private func observeSettings() {
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.settingsDidChange() }
            .store(in: &cancellables)
    }

    /// The one path through which a defaults write reaches the live window,
    /// the status item and the sampling loop.
    private func settingsDidChange() {
        refreshMenuTitles()
        UpdateChecker.shared.settingsChanged()

        let demand = SamplingDemand.current()
        let showHUD = SettingsStore.shared.showHUD
        let showChanged = showHUD != lastShowHUD
        if demand != lastDemand || showChanged {
            lastDemand = demand
            lastShowHUD = showHUD
            // A metric or column change must take effect now, not after the
            // current refresh interval. The loop re-reads demand before the
            // next sample and parks itself if nothing is visible.
            metrics.wake()
        }

        syncOverlayMembership()
        applyHUDFrameIfChanged()
        updateOverlayState()
        if showChanged, showHUD {
            reposition()
        }
        updateStatusBarTitle()
    }

    /// Repositions the HUD when a corner or margin setting changes (including
    /// a reset or a write from another process), without reacting to unrelated
    /// defaults writes such as a font or opacity slider.
    private func applyHUDFrameIfChanged() {
        let store = SettingsStore.shared
        let changed = store.hudCorner != lastHUDCorner
            || store.hudMarginHorizontal != lastHUDHorizontalMargin
            || store.hudMarginVertical != lastHUDVerticalMargin
        guard changed else { return }
        lastHUDCorner = store.hudCorner
        lastHUDHorizontalMargin = store.hudMarginHorizontal
        lastHUDVerticalMargin = store.hudMarginVertical
        reposition()
    }

    /// Installs the setting on the live window. A collection-behaviour change
    /// only takes effect for the Space the user is on when the window is
    /// re-ordered along with it, so the swap is: order out, change membership,
    /// order back in where the window now belongs.
    ///
    /// Ordering it front *regardless* of where it belongs is what strands a
    /// window outside every desktop Space, so the HUD is only brought back when
    /// it belongs on the active Space — after a swap to "off" while the user is
    /// inside a full-screen Space that means staying out, which is the intended
    /// result anyway.
    private func syncOverlayMembership() {
        guard let w = window else { return }
        let show = SettingsStore.shared.showInFullscreen
        guard show != appliedShowInFullscreen else { return }
        appliedShowInFullscreen = show

        w.orderOut(nil)
        w.collectionBehavior = OverlaySpacePolicy.collectionBehavior(showInFullscreen: show)
        if SettingsStore.shared.showHUD, show || w.isOnActiveSpace {
            w.orderFrontRegardless()
        }

        // `isOnActiveSpace` can still describe the previous membership for a
        // moment, so the state is read once more after the swap settles.
        membershipSettle?.cancel()
        membershipSettle = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.updateOverlayState()
        }
        updateOverlayState()
    }

    /// Reads which surfaces are actually on screen right now and puts sampling
    /// to sleep with the ones that are not.
    ///
    /// Two independent switches matter: the manual "Show HUD" setting combined
    /// with the window server's Space membership decides whether the HUD is
    /// displayed, and the status item's real visibility decides whether the
    /// menu bar readout is. Nothing visible means no sensor is read at all.
    private func updateOverlayState(refreshStatusBarVisibility: Bool = false) {
        guard let w = window else { return }

        let showHUD = SettingsStore.shared.showHUD
        if showHUD {
            // A swap that leaves the HUD ordered out although it belongs on the
            // active Space would keep it hidden until the next Space change;
            // order it back in. (With the overlay off inside a full-screen Space
            // the window does not belong there, so this stays quiet.)
            if !w.isVisible, w.isOnActiveSpace {
                w.orderFrontRegardless()
            }
        } else if w.isVisible {
            w.orderOut(nil)
        }

        let hudVisible = showHUD && OverlaySpacePolicy.isDisplayed(w)
        // The status item's visibility is only re-probed on Space changes and
        // by the light monitor; routine settings writes reuse the last answer so
        // a slider drag never pays for a window-server query per frame.
        if refreshStatusBarVisibility || lastStatusBarVisible == nil {
            lastStatusBarVisible = isStatusBarVisible()
        }
        let statusBarVisible = lastStatusBarVisible ?? true

        metrics.setScope(
            SamplingScope.resolve(hudVisible: hudVisible, statusBarVisible: statusBarVisible)
        )
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
        // The membership is set at creation from the current setting, which is
        // what makes a launch while the user sits in a full-screen Space
        // correct from the first frame — with the overlay off the HUD never
        // appears there at all, rather than appearing and being ordered away.
        w.collectionBehavior = OverlaySpacePolicy.collectionBehavior(
            showInFullscreen: SettingsStore.shared.showInFullscreen
        )
        appliedShowInFullscreen = SettingsStore.shared.showInFullscreen
        w.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: HUDView(metrics: metrics))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = hosting

        let delegate = WindowDelegate(
            onResize: { [weak self, weak w] in
                self?.scheduleSizeSave(w)
                self?.reposition()
                self?.scheduleReanchor()
            }
        )
        hudWindowDelegate = delegate
        w.delegate = delegate

        // orderFrontRegardless rather than makeKeyAndOrderFront: a borderless
        // window never becomes key, and showing the HUD over a full-screen app
        // must not pull focus away from it. A launch with the HUD switched off
        // creates the window without showing it.
        if SettingsStore.shared.showHUD {
            w.orderFrontRegardless()
        }
        window = w
        updateOverlayState(refreshStatusBarVisibility: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.initialFrameSaveDelay) { [weak self, weak w] in
            self?.saveSize(w)
            self?.reposition()
        }
    }

    /// Snaps the HUD to the selected corner of the screen it is on. The
    /// persisted setting is the single source of truth for launch, corner
    /// changes and content-driven resizes.
    private func reposition() {
        guard let w = window, !isRepositioning else { return }
        let screen = w.screen ?? preferredScreen
        guard let screen else { return }
        // Use the live window size, not the debounced saved size: a
        // right-anchored HUD must keep its right edge fixed while SwiftUI
        // grows it for new columns or a larger font.
        let target = hudFrame(for: screen, size: w.frame.size)
        guard w.frame != target else { return }
        isRepositioning = true
        w.setFrame(target, display: true, animate: false)
        isRepositioning = false
    }

    /// Re-anchors after SwiftUI changes the window's content size. Debounced
    /// so a layout pass does not repeatedly move the window.
    private func scheduleReanchor() {
        reanchorTimer?.invalidate()
        reanchorTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.reposition() }
        }
    }

    private func scheduleSizeSave(_ w: NSWindow?) {
        saveSizeTimer?.invalidate()
        saveSizeTimer = Timer.scheduledTimer(withTimeInterval: Self.sizeSaveDebounce, repeats: false) { [weak self, weak w] _ in
            guard let self, let w else { return }
            Task { @MainActor in self.saveSize(w) }
        }
    }

    private func saveSize(_ w: NSWindow?) {
        guard let w else { return }
        let size = w.frame.size
        SettingsStore.shared.hudWidth = size.width
        SettingsStore.shared.hudHeight = size.height
    }

    /// The corner is the persisted position; the saved size is only a hint for
    /// the first layout, then the window auto-sizes to its SwiftUI content.
    private func hudFrame(for screen: NSScreen) -> NSRect {
        let store = SettingsStore.shared
        let size: CGSize
        if store.hudWidth > 0, store.hudHeight > 0 {
            size = CGSize(width: store.hudWidth, height: store.hudHeight)
        } else {
            size = HUDFrame.defaultSize
        }
        return hudFrame(for: screen, size: size)
    }

    private func hudFrame(for screen: NSScreen, size: CGSize) -> NSRect {
        let store = SettingsStore.shared
        let position = HUDPosition(rawValue: store.hudCorner) ?? .bottomLeft
        return position.frame(
            for: size,
            screenFrame: screen.frame,
            topEdge: screen.visibleFrame.maxY,
            horizontalMargin: CGFloat(store.hudMarginHorizontal),
            verticalMargin: CGFloat(store.hudMarginVertical)
        )
    }

    // MARK: - Status Bar

    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let view = MenubarContentView()

        let menu = NSMenu()
        // The update item is enabled/disabled explicitly; auto-validation can
        // otherwise disable programmatic actions whose targets are the
        // AppDelegate.
        menu.autoenablesItems = false
        menu.delegate = self
        menu.appearance = NSApp.effectiveAppearance

        let hudItem = NSMenuItem(
            title: LocaleManager.shared.localized("Show HUD"),
            action: #selector(toggleHUD),
            keyEquivalent: ""
        )
        hudItem.target = self
        hudItem.state = SettingsStore.shared.showHUD ? .on : .off
        hudItem.image = NSImage(
            systemSymbolName: SettingsStore.shared.showHUD ? "eye" : "eye.slash",
            accessibilityDescription: LocaleManager.shared.localized("Show HUD")
        )
        menu.addItem(hudItem)
        hudMenuItem = hudItem

        menu.addItem(NSMenuItem.separator())

        let infoItem = NSMenuItem(
            title: LocaleManager.shared.localized("Device Information..."),
            action: #selector(openDeviceInfo),
            keyEquivalent: "i"
        )
        infoItem.target = self
        infoItem.image = NSImage(
            systemSymbolName: "desktopcomputer",
            accessibilityDescription: LocaleManager.shared.localized("Device Information")
        )
        menu.addItem(infoItem)
        infoMenuItem = infoItem

        let guideItem = NSMenuItem(
            title: LocaleManager.shared.localized("User Guide"),
            action: #selector(openGuide),
            keyEquivalent: ""
        )
        guideItem.target = self
        guideItem.image = NSImage(
            systemSymbolName: "book",
            accessibilityDescription: LocaleManager.shared.localized("User Guide")
        )
        menu.addItem(guideItem)
        guideMenuItem = guideItem

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(
            title: LocaleManager.shared.localized("Check for Updates…"),
            action: #selector(performUpdateAction),
            keyEquivalent: ""
        )
        updateItem.target = self
        updateItem.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: LocaleManager.shared.localized("Check for Updates…")
        )
        menu.addItem(updateItem)
        updateMenuItem = updateItem

        let settingsItem = NSMenuItem(
            title: LocaleManager.shared.localized("Settings..."),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        settingsMenuItem = settingsItem

        let aboutItem = NSMenuItem(
            title: LocaleManager.shared.localized("About Semono"),
            action: #selector(openAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        aboutItem.image = NSImage(
            systemSymbolName: "info.circle",
            accessibilityDescription: LocaleManager.shared.localized("About Semono")
        )
        menu.addItem(aboutItem)
        aboutMenuItem = aboutItem

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: LocaleManager.shared.localized("Quit Semono"),
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
        quitMenuItem = quitItem
        view.menu = menu

        // Configure the readout before the view is inserted: icon-only mode is
        // paused, so there may be no later metric change to make the menu bar
        // take a fresh snapshot of the view.
        menubarView = view
        updateStatusBarTitle()
        statusItem?.view = view
        observeUpdateChecker()
        UpdateChecker.shared.start()

        // Icon-only mode is paused, so an update of the readout never comes.
        // A couple of late invalidations let the item settle into the menu bar
        // before the system takes its snapshot.
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                view?.needsDisplay = true
            }
        }
    }

    private func updateStatusBarTitle() {
        let metric = StatusBarMetric(rawValue: SettingsStore.shared.statusBarMetric) ?? .cpu
        let readout = metric.readout(from: metrics)
        guard let view = menubarView else { return }
        if view.readout != readout {
            view.readout = readout
        }
        guard !view.isChecking else { return }
        let width = max(Self.statusBarMinWidth, view.fittingWidth)
        if statusItem?.length != width {
            statusItem?.length = width
        }
        // The view's setter already invalidates; this also covers the launch
        // path (readout unchanged) and the delayed icon snapshot.
        view.needsDisplay = true
    }

    private func showFirstRunGuideIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.firstRunGuideKey) else { return }
        defaults.set(true, forKey: Self.firstRunGuideKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSApp.activate()
            WindowRouter.openGuide?()
        }
    }

    private func observeUpdateChecker() {
        let checker = UpdateChecker.shared
        updateCheckerStateChanged(checker.state)
        checker.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.updateCheckerStateChanged(state) }
            .store(in: &cancellables)
    }

    private func updateCheckerStateChanged(_ state: UpdateChecker.State) {
        let checking = UpdateChecker.shared.isChecking
        menubarView?.isChecking = checking
        if checking {
            statusItem?.length = 24
        } else {
            updateStatusBarTitle()
        }
        refreshUpdateMenuState()
    }

    private func refreshUpdateMenuState() {
        guard let item = updateMenuItem else { return }
        let locale = LocaleManager.shared
        let checker = UpdateChecker.shared
        if checker.isChecking {
            item.title = locale.localized("Checking for Updates…")
            item.isEnabled = false
            item.action = nil
        } else if checker.hasUpdate {
            item.title = locale.localized("Go to Update")
            item.isEnabled = true
            item.action = #selector(performUpdateAction)
        } else {
            item.title = locale.localized("Check for Updates…")
            item.isEnabled = true
            item.action = #selector(performUpdateAction)
        }
        item.image = NSImage(
            systemSymbolName: checker.hasUpdate ? "arrow.down.circle.fill" : "arrow.triangle.2.circlepath",
            accessibilityDescription: item.title
        )
    }

    /// AppKit menu titles are not SwiftUI-localized, so a language change is
    /// reflected the next time the menu opens.
    private func refreshMenuTitles() {
        let locale = LocaleManager.shared
        hudMenuItem?.title = locale.localized("Show HUD")
        infoMenuItem?.title = locale.localized("Device Information...")
        guideMenuItem?.title = locale.localized("User Guide")
        settingsMenuItem?.title = locale.localized("Settings...")
        aboutMenuItem?.title = locale.localized("About Semono")
        quitMenuItem?.title = locale.localized("Quit Semono")
        refreshHUDMenuState()
        refreshUpdateMenuState()
    }

    /// Keeps the checkmark and the eye glyph in step with the persisted
    /// setting, including writes made by another process.
    private func refreshHUDMenuState() {
        let desired: NSControl.StateValue = SettingsStore.shared.showHUD ? .on : .off
        guard let item = hudMenuItem, item.state != desired else { return }
        item.state = desired
        item.image = NSImage(
            systemSymbolName: desired == .on ? "eye" : "eye.slash",
            accessibilityDescription: LocaleManager.shared.localized("Show HUD")
        )
    }

    /// True while the status item can actually be seen. NSStatusItem.isVisible
    /// does not account for a full-screen Space hiding the menu bar, so the
    /// item window's visibility/occlusion state and the window server's menu
    /// bar window are consulted as well.
    private func isStatusBarVisible() -> Bool {
        guard let item = statusItem else { return false }
        let window = item.view?.window
        return StatusBarVisibility.isVisible(
            itemVisible: item.isVisible,
            windowExists: window != nil,
            windowVisible: window?.isVisible ?? true,
            windowOcclusionVisible: window?.occlusionState.contains(.visible) ?? true,
            menuBarOnScreen: MenuBarProbe.isOnScreen()
        )
    }

    /// The menu bar can be hidden and revealed without a Space change, so a
    /// light probe keeps the sampling scope honest while the HUD is out of the
    /// way. It reads metadata only; no metric is sampled here.
    private func startStatusBarVisibilityMonitoring() {
        statusBarVisibilityTimer?.invalidate()
        lastStatusBarVisible = isStatusBarVisible()
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let visible = self.isStatusBarVisible()
                guard visible != self.lastStatusBarVisible else { return }
                self.updateOverlayState(refreshStatusBarVisibility: true)
            }
        }
        timer.tolerance = 0.25
        statusBarVisibilityTimer = timer
    }

    // MARK: - HUD Toggle

    @objc private func toggleHUD() {
        SettingsStore.shared.showHUD.toggle()
        refreshHUDMenuState()
        updateOverlayState()
        if SettingsStore.shared.showHUD {
            reposition()
        }
        metrics.wake()
    }

    // MARK: - Window Opening

    @objc private func openDeviceInfo() {
        NSApp.activate()
        WindowRouter.openDeviceInfo?()
    }

    @objc private func openSettings() {
        NSApp.activate()
        syncLoginItemState()
        WindowRouter.openSettings?()
    }

    @objc private func openGuide() {
        NSApp.activate()
        WindowRouter.openGuide?()
    }

    @objc private func openAbout() {
        NSApp.activate()
        WindowRouter.openAbout?()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // The status menu otherwise inherits the menu bar's vibrant appearance,
        // which can be dark even when the app windows and system menus are
        // light. Follow the app's effective appearance instead.
        menu.appearance = NSApp.effectiveAppearance
        // Refresh the update entry at the last moment so a check that finished
        // while the menu was closed is reflected immediately.
        refreshUpdateMenuState()
    }

    @objc private func performUpdateAction() {
        if UpdateChecker.shared.hasUpdate {
            UpdateChecker.shared.openRelease()
        } else {
            UpdateChecker.shared.checkForUpdates(manual: true)
        }
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
    let onResize: (() -> Void)?

    init(onResize: (() -> Void)? = nil) {
        self.onResize = onResize
    }

    func windowDidResize(_ notification: Notification) { onResize?() }
}
