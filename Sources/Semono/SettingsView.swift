import SwiftUI
import ServiceManagement
import Foundation

/// One page of the settings window. The sidebar groups these the same way the
/// Device Information window groups profiler data types.
enum SettingsGroup: String, CaseIterable, Identifiable, Hashable {
    case hud
    case application

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .hud: "HUD"
        case .application: "Application"
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case hud
    case appearance
    case columns
    case menuBar
    case general

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hud: "eye"
        case .appearance: "paintbrush"
        case .columns: "rectangle.grid.2x2"
        case .menuBar: "menubar.rectangle"
        case .general: "gearshape"
        }
    }

    var tint: Color {
        switch self {
        case .hud: .blue
        case .appearance: .purple
        case .columns: .green
        case .menuBar: .teal
        case .general: .indigo
        }
    }

    var titleKey: String {
        switch self {
        case .hud: "HUD"
        case .appearance: "Appearance"
        case .columns: "Columns"
        case .menuBar: "Menu Bar"
        case .general: "General"
        }
    }

    var subtitleKey: String {
        switch self {
        case .hud: "Visibility, position and refresh of the floating HUD."
        case .appearance: "Background, display style and typography."
        case .columns: "Choose which metrics the HUD shows."
        case .menuBar: "What the menu bar icon readout shows."
        case .general: "Startup, language and reset."
        }
    }

    var group: SettingsGroup {
        switch self {
        case .hud, .appearance, .columns, .menuBar: .hud
        case .general: .application
        }
    }

    static func sections(in group: SettingsGroup) -> [SettingsSection] {
        allCases.filter { $0.group == group }
    }
}

/// Settings on the same visual language as Device Information: a grouped
/// sidebar, a tinted header, and rounded cards with quiet secondary labels.
struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var locale = LocaleManager.shared
    @State private var selection: SettingsSection? = SettingsView.initialSection
    @State private var showLoginError = false
    @State private var loginErrorMessage = ""
    /// Guards the launch-at-login toggle against its own failure rollback:
    /// when registration fails the toggle is reverted, and the change fired
    /// by that revert must not run the register/unregister flow again.
    @State private var pendingLoginChange: Bool?

    private func t(_ key: String) -> String { locale.localized(key) }

    private var selectedStatusBarMetric: StatusBarMetric {
        StatusBarMetric(rawValue: settings.statusBarMetric) ?? .cpu
    }

    private var selectedHUDPosition: HUDPosition {
        HUDPosition(rawValue: settings.hudCorner) ?? .bottomLeft
    }

    /// Debug-only hook used by screenshot automation; release builds always
    /// open on HUD.
    private static var initialSection: SettingsSection {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["SEMONO_SETTINGS_PAGE"],
           let section = SettingsSection(rawValue: raw) {
            return section
        }
        #endif
        return .hud
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 250)
        } detail: {
            if let selection {
                SettingsDetailView(section: selection, locale: locale) {
                    detailContent(for: selection)
                }
                .id(selection)
            } else {
                ContentUnavailableView(
                    t("Semono Settings"),
                    systemImage: "gearshape",
                    description: Text(t("Choose a settings page."))
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle(t("Semono Settings"))
        .frame(minWidth: 780, minHeight: 560)
        .background(WindowRegistration(window: .settings))
        .alert(t("Launch at Login Failed"), isPresented: $showLoginError) {
            Button("OK") {}
        } message: {
            Text("\(t("Login item failed to register. It may require a properly signed build."))\n\(loginErrorMessage)")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SettingsGroup.allCases) { group in
                    Section {
                        ForEach(SettingsSection.sections(in: group)) { section in
                            SettingsSidebarRow(
                                section: section,
                                title: t(section.titleKey)
                            )
                            .tag(section)
                        }
                    } header: {
                        Text(t(group.titleKey))
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                Text(t("Settings apply immediately"))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func detailContent(for section: SettingsSection) -> some View {
        switch section {
        case .hud: hudPage
        case .appearance: appearancePage
        case .columns: columnsPage
        case .menuBar: menuBarPage
        case .general: generalPage
        }
    }

    private var hudPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: t("Visibility"), icon: "eye") {
                SettingsToggleRow(
                    title: t("Show HUD"),
                    description: t("Controls whether the floating HUD is shown."),
                    isOn: $settings.showHUD
                )
                SettingsToggleRow(
                    title: t("Show in Fullscreen"),
                    description: t("Keep the HUD visible over full-screen apps."),
                    isOn: $settings.showInFullscreen
                )
            }

            positionCard

            SettingsCard(title: t("Refresh"), icon: "clock.arrow.circlepath") {
                SettingsRow(
                    title: t("Refresh"),
                    description: t("How often live metrics are read.")
                ) {
                    Picker("", selection: $settings.refreshInterval) {
                        ForEach(SettingsStore.refreshOptions, id: \.self) { seconds in
                            Text("\(seconds)\(locale.localized("s"))").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsNote(
                text: t("When the HUD is hidden, only a visible menu bar readout keeps updating."),
                icon: "menubar.rectangle"
            )
        }
    }

    private var positionCard: some View {
        SettingsCard(title: t("Position"), icon: "rectangle.inset.filled") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 10
                ) {
                    ForEach(HUDPosition.allCases) { position in
                        positionButton(position)
                    }
                }

                SettingsRow(
                    title: t("Horizontal Margin"),
                    description: t("Distance from the left or right screen edge.")
                ) {
                    marginControl($settings.hudMarginHorizontal)
                }

                SettingsRow(
                    title: t("Vertical Margin"),
                    description: t("Distance from the top or bottom screen edge.")
                ) {
                    marginControl($settings.hudMarginVertical)
                }

            }
        }
    }

    private func marginControl(_ value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: 0...40, step: 1)
                .frame(width: 150)
            Text("\(Int(value.wrappedValue)) \(locale.localized("pt"))")
                .font(.system(.callout, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
    }

    private func positionButton(_ position: HUDPosition) -> some View {
        let selected = selectedHUDPosition == position
        return Button {
            settings.hudCorner = position.rawValue
        } label: {
            HStack(spacing: 8) {
                Image(systemName: position.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                Text(t(position.titleKey))
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                (selected ? Color.accentColor : Color.secondary).opacity(selected ? 0.12 : 0.05),
                in: .rect(cornerRadius: 8)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var appearancePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: t("Background"), icon: "rectangle.inset.filled") {
                SettingsRow(
                    title: t("Opacity"),
                    description: t("Transparency of the HUD background.")
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $settings.backgroundOpacity, in: 0.0...1.0, step: 0.05)
                            .frame(width: 190)
                        Text("\(Int(settings.backgroundOpacity * 100))%")
                            .font(.system(.callout, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                SettingsToggleRow(
                    title: t("Block Display"),
                    description: t("Draw percentage metrics as block bars instead of digits."),
                    isOn: $settings.useBlockDisplay
                )
            }

            SettingsCard(title: t("Typography"), icon: "textformat") {
                SettingsRow(
                    title: t("Font"),
                    description: t("Fixed-pitch face used by the HUD.")
                ) {
                    Picker("", selection: $settings.fontName) {
                        ForEach(settings.availableFonts, id: \.name) { font in
                            Text(font.label).tag(font.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 208)
                    .onAppear { settings.loadAvailableFontsIfNeeded() }
                }
                SettingsRow(
                    title: t("Font Scale"),
                    description: t("Adjust the HUD type size without changing its layout.")
                ) {
                    HStack(spacing: 10) {
                        Slider(value: $settings.fontScale, in: -5...10, step: 1)
                            .frame(width: 190)
                        Text("\(Int(settings.fontScale))")
                            .font(.system(.callout, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var columnsPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: t("HUD Columns"), icon: "rectangle.grid.2x2") {
                SettingsToggleRow(
                    title: t("Compute (CPU/GPU/PWR)"),
                    description: t("CPU, GPU and power draw."),
                    isOn: $settings.showComputeColumn
                )
                SettingsToggleRow(
                    title: t("Memory (MEM/PRS/SWAP)"),
                    description: t("Memory usage, pressure level and swap."),
                    isOn: $settings.showMemoryColumn
                )
                SettingsToggleRow(
                    title: t("Storage (DR/DW/THM)"),
                    description: t("Disk read/write throughput and thermal pressure."),
                    isOn: $settings.showStorageColumn
                )
                SettingsToggleRow(
                    title: t("Network (NET/UP/DN)"),
                    description: t("Connection type, Wi-Fi signal and upload/download speed."),
                    isOn: $settings.showNetworkColumn
                )
            }

            SettingsNote(
                text: t("A hidden or disabled column is not sampled while the HUD is the only visible surface."),
                icon: "leaf"
            )
        }
    }

    private var menuBarPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: t("Menu Bar Metric"), icon: "menubar.rectangle") {
                VStack(spacing: 0) {
                    ForEach(StatusBarMetric.allCases) { metric in
                        if metric != .cpu {
                            Divider().opacity(0.5)
                        }
                        metricRow(metric)
                    }
                }
            }

            SettingsNote(
                text: t("The menu bar is the only readout while the HUD is hidden; icon-only mode stops live sampling."),
                icon: "eye.slash"
            )
        }
    }

    private func metricRow(_ metric: StatusBarMetric) -> some View {
        let selected = selectedStatusBarMetric == metric
        return Button {
            settings.statusBarMetric = metric.rawValue
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: metric.settingsIcon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (selected ? Color.accentColor : Color.secondary).opacity(0.12),
                        in: .rect(cornerRadius: 7)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(t(metric.settingsTitleKey))
                        .font(.callout.weight(selected ? .semibold : .regular))
                    Text(t(metric.settingsDescriptionKey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.35))
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var generalPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: t("Startup"), icon: "power") {
                SettingsToggleRow(
                    title: t("Launch at Login"),
                    description: t("Start Semono when you log in."),
                    isOn: $settings.launchAtLogin
                )
                .onChange(of: settings.launchAtLogin) { _, newValue in
                    guard pendingLoginChange != newValue else { return }
                    pendingLoginChange = newValue
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        pendingLoginChange = nil
                    } catch {
                        // Registration is rejected on ad-hoc-signed builds;
                        // revert the toggle to the real status and surface the
                        // failure instead of staying silent. (SMAppService
                        // errors are cryptic SMAppServiceErrorDomain codes,
                        // hence the hint in the alert.)
                        let status = SMAppService.mainApp.status == .enabled
                        pendingLoginChange = status
                        settings.launchAtLogin = status
                        loginErrorMessage = error.localizedDescription
                        showLoginError = true
                    }
                }
            }

            SettingsCard(title: t("Language"), icon: "globe") {
                SettingsRow(
                    title: t("Language"),
                    description: t("Language used by Semono's interface.")
                ) {
                    Picker("", selection: Binding(
                        get: { locale.currentLanguage.rawValue },
                        set: { settings.appLanguage = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName(in: locale.currentLanguage)).tag(language.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SettingsCard(title: t("Reset"), icon: "arrow.counterclockwise") {
                SettingsRow(
                    title: t("Restore Defaults"),
                    description: t("Reset every preference, including the HUD position.")
                ) {
                    Button {
                        settings.resetToDefaults()
                    } label: {
                        Label(t("Restore Defaults"), systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.regular)
                }
            }
        }
    }
}

// MARK: - Sidebar row

private struct SettingsSidebarRow: View {
    let section: SettingsSection
    let title: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: section.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(section.tint)
                .frame(width: 20, height: 20)
                .background(section.tint.opacity(0.13), in: .rect(cornerRadius: 5))

            Text(title)
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Detail chrome

private struct SettingsDetailView<Content: View>: View {
    let section: SettingsSection
    @ObservedObject var locale: LocaleManager
    private let content: Content

    init(
        section: SettingsSection,
        locale: LocaleManager,
        @ViewBuilder content: () -> Content
    ) {
        self.section = section
        self.locale = locale
        self.content = content()
    }

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: section.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(section.tint)
                .frame(width: 46, height: 46)
                .background(section.tint.opacity(0.14), in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(t(section.titleKey))
                    .font(.system(size: 26, weight: .semibold))
                Text(t(section.subtitleKey))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let icon: String
    private let content: Content

    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 20, height: 20)
                    .background(.tint.opacity(0.12), in: .rect(cornerRadius: 6))
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        }
    }
}

private struct SettingsRow<Control: View>: View {
    let title: String
    let description: String?
    private let control: () -> Control

    init(title: String, description: String? = nil, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.description = description
        self.control = control
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control()
                .frame(minWidth: 168, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool

    init(title: String, description: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.description = description
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                if let description {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel(Text(title))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsNote: View {
    let text: String
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 2)
    }
}
