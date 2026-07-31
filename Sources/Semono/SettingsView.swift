import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable {
    case display, columns, general
}

final class SettingsViewState: ObservableObject {
    @Published var selectedTab: SettingsTab = .display
}

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var locale = LocaleManager.shared
    @ObservedObject private var state = SettingsViewState()
    let restartAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.selectedTab) {
                Text(locale.localized("Display")).tag(SettingsTab.display)
                Text(locale.localized("Columns")).tag(SettingsTab.columns)
                Text(locale.localized("General")).tag(SettingsTab.general)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider()
                .padding(.horizontal, 12)

            ScrollView {
                tabContent
                    .padding(16)
            }

            Divider()
                .padding(.horizontal, 12)

            HStack {
                Spacer()
                Button(locale.localized("Apply")) {
                    restartAction()
                }
                .keyboardShortcut(.return)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(width: 320, height: 400)
        .fixedSize()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch state.selectedTab {
        case .display: displayTab
        case .columns: columnsTab
        case .general: generalTab
        }
    }

    // MARK: - Display Tab

    private var displayTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(locale.localized("Opacity")): \(Int(settings.backgroundOpacity * 100))%")
                    .font(.caption)
                Slider(value: $settings.backgroundOpacity, in: 0.0...1.0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("\(locale.localized("Font Scale")): \(Int(settings.fontScale))")
                    .font(.caption)
                Slider(value: $settings.fontScale, in: -5...10, step: 1)
            }

            HStack {
                Text(locale.localized("Font:"))
                    .font(.caption)
                Spacer()
                Picker("", selection: $settings.fontName) {
                    ForEach(SettingsStore.availableFonts, id: \.name) { f in
                        Text(f.label).tag(f.name)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }

            Toggle(locale.localized("Show in Fullscreen"), isOn: $settings.showInFullscreen)
            Toggle(locale.localized("Block Display"), isOn: $settings.useBlockDisplay)
        }
    }

    // MARK: - Columns Tab

    private var columnsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(locale.localized("Compute (CPU/GPU/PWR)"), isOn: $settings.showComputeColumn)
            Toggle(locale.localized("Memory (MEM/PRS/SWAP)"), isOn: $settings.showMemoryColumn)
            Toggle(locale.localized("Storage (DR/DW/THM)"),  isOn: $settings.showStorageColumn)
            Toggle(locale.localized("Network (NET/UP/DN)"),   isOn: $settings.showNetworkColumn)

            Divider()

            Text(locale.localized("Menu Bar"))
                .font(.caption).foregroundColor(.secondary)
            Picker("", selection: $settings.statusBarMetric) {
                Text("CPU").tag("cpu")
                Text("GPU").tag("gpu")
                Text("PWR").tag("pwr")
                Text("MEM").tag("memory")
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(locale.localized("Refresh:"))
                    .font(.caption)
                Spacer()
                Picker("", selection: $settings.refreshInterval) {
                    Text("1s").tag(1)
                    Text("2s").tag(2)
                    Text("3s").tag(3)
                    Text("5s").tag(5)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Toggle(locale.localized("Launch at Login"), isOn: loginBinding)

            HStack {
                Text(locale.localized("Language:"))
                    .font(.caption)
                Spacer()
                Picker("", selection: $settings.appLanguage) {
                    Text(locale.localized("English")).tag("en")
                    Text(locale.localized("中文")).tag("zh")
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
        }
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    settings.launchAtLogin = newValue
                } catch {
                    settings.launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }
        )
    }
}
