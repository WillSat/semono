import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case display, columns, general

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .display: "display"
        case .columns: "rectangle.grid.2x2"
        case .general: "gearshape"
        }
    }

    var titleKey: String {
        switch self {
        case .display: "Display"
        case .columns: "Columns"
        case .general: "General"
        }
    }
}

/// Standard macOS settings on the macOS 26/27 design language: sidebar-
/// adaptable TabView (Liquid Glass sidebar on macOS 26+) with icon-led
/// grouped sections in the System Settings style.
struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var locale = LocaleManager.shared
    @State private var selectedTab: SettingsTab = .display
    @State private var showLoginError = false
    @State private var loginErrorMessage = ""
    /// Guards the launch-at-login toggle against its own failure rollback:
    /// when registration fails the toggle is reverted, and the change fired
    /// by that revert must not run the register/unregister flow again.
    @State private var pendingLoginChange: Bool?

    var body: some View {
        TabView(selection: $selectedTab) {
            displayTab
                .tabItem {
                    Label(locale.localized(SettingsTab.display.titleKey), systemImage: SettingsTab.display.icon)
                }
                .tag(SettingsTab.display)

            columnsTab
                .tabItem {
                    Label(locale.localized(SettingsTab.columns.titleKey), systemImage: SettingsTab.columns.icon)
                }
                .tag(SettingsTab.columns)

            generalTab
                .tabItem {
                    Label(locale.localized(SettingsTab.general.titleKey), systemImage: SettingsTab.general.icon)
                }
                .tag(SettingsTab.general)
        }
        .tabViewStyle(.sidebarAdaptable)
        .toolbar(removing: .sidebarToggle)
        .alert(locale.localized("Launch at Login Failed"), isPresented: $showLoginError) {
            Button("OK") {}
        } message: {
            Text("\(locale.localized("Login item failed to register. It may require a properly signed build."))\n\(loginErrorMessage)")
        }
    }

    // MARK: - Display

    private var displayTab: some View {
        Form {
            Section {
                LabeledContent(locale.localized("Opacity")) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.backgroundOpacity, in: 0.0...1.0, step: 0.05)
                            .frame(width: 170)
                        Text("\(Int(settings.backgroundOpacity * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                Toggle(locale.localized("Show in Fullscreen"), isOn: $settings.showInFullscreen)
                Toggle(locale.localized("Block Display"), isOn: $settings.useBlockDisplay)
            } header: {
                SettingsSectionHeader(icon: "rectangle.inset.filled", title: locale.localized("Window"))
            }

            Section {
                LabeledContent(locale.localized("Font")) {
                    Picker("", selection: $settings.fontName) {
                        ForEach(SettingsStore.availableFonts, id: \.name) { f in
                            Text(f.label).tag(f.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
                LabeledContent(locale.localized("Font Scale")) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.fontScale, in: -5...10, step: 1)
                            .frame(width: 170)
                        Text("\(Int(settings.fontScale))")
                            .font(.system(.body, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                }
            } header: {
                SettingsSectionHeader(icon: "textformat", title: locale.localized("Font"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Columns

    private var columnsTab: some View {
        Form {
            Section {
                Toggle(locale.localized("Compute (CPU/GPU/PWR)"), isOn: $settings.showComputeColumn)
                Toggle(locale.localized("Memory (MEM/PRS/SWAP)"), isOn: $settings.showMemoryColumn)
                Toggle(locale.localized("Storage (DR/DW/THM)"), isOn: $settings.showStorageColumn)
                Toggle(locale.localized("Network (NET/UP/DN)"), isOn: $settings.showNetworkColumn)
            } header: {
                SettingsSectionHeader(icon: "rectangle.grid.2x2", title: locale.localized("Columns"))
            }

            Section {
                Picker("", selection: $settings.statusBarMetric) {
                    Text("CPU").tag("cpu")
                    Text("GPU").tag("gpu")
                    Text("PWR").tag("pwr")
                    Text("MEM").tag("memory")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: {
                SettingsSectionHeader(icon: "menubar.rectangle", title: locale.localized("Menu Bar"))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                LabeledContent(locale.localized("Refresh")) {
                    Picker("", selection: $settings.refreshInterval) {
                        Text("1s").tag(1)
                        Text("2s").tag(2)
                        Text("3s").tag(3)
                        Text("5s").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 150)
                }
                Toggle(locale.localized("Launch at Login"), isOn: $settings.launchAtLogin)
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
                            // Registration is rejected on ad-hoc-signed
                            // builds; revert the toggle to the real status
                            // and surface the failure instead of staying
                            // silent. (SMAppService errors are cryptic
                            // SMAppServiceErrorDomain codes, hence the hint.)
                            let status = SMAppService.mainApp.status == .enabled
                            pendingLoginChange = status
                            settings.launchAtLogin = status
                            loginErrorMessage = error.localizedDescription
                            showLoginError = true
                        }
                    }
            } header: {
                SettingsSectionHeader(icon: "gearshape", title: locale.localized("General"))
            }

            Section {
                LabeledContent(locale.localized("Language")) {
                    Picker("", selection: $settings.appLanguage) {
                        Text(locale.localized("English")).tag("en")
                        Text(locale.localized("中文")).tag("zh")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            } header: {
                SettingsSectionHeader(icon: "globe", title: locale.localized("Language"))
            }

            Section {
                Button {
                    settings.resetToDefaults()
                } label: {
                    Label(locale.localized("Restore Defaults"), systemImage: "arrow.counterclockwise")
                }
            } header: {
                SettingsSectionHeader(icon: "arrow.counterclockwise", title: locale.localized("Reset"))
            }

            Section {
                Text(locale.localized("Settings apply immediately"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Section Header

/// Grouped-section header in the macOS 26 System Settings style: a small
/// tinted icon chip beside a semibold label.
private struct SettingsSectionHeader: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 20, height: 20)
                .background(.tint.opacity(0.12), in: .rect(cornerRadius: 6))
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.secondary)
    }
}
