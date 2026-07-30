import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings = SettingsStore.shared
    let restartAction: () -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Opacity: \(Int(settings.backgroundOpacity * 100))%")
                        .font(.caption)
                    Slider(value: $settings.backgroundOpacity, in: 0.0...1.0)
                }
                .padding(.vertical, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Font Scale: \(Int(settings.fontScale))")
                        .font(.caption)
                    Slider(value: $settings.fontScale, in: -5...10, step: 1)
                }
                .padding(.vertical, 2)

                Picker("Font:", selection: $settings.fontName) {
                    ForEach(SettingsStore.availableFonts, id: \.name) { f in
                        Text(f.label).tag(f.name)
                    }
                }

                Toggle("Show in Fullscreen", isOn: $settings.showInFullscreen)
                Toggle("Block Display", isOn: $settings.useBlockDisplay)
            } header: {
                Text("Display")
            }

            Section {
                Toggle("Compute (CPU/GPU/PWR)", isOn: $settings.showComputeColumn)
                Toggle("Memory (MEM/PRS/SWAP)", isOn: $settings.showMemoryColumn)
                Toggle("Storage (DR/DW/THM)",  isOn: $settings.showStorageColumn)
                Toggle("Network (NET/UP/DN)",   isOn: $settings.showNetworkColumn)
            } header: {
                Text("Columns")
            }

            Section {
                Picker("Menu Bar:", selection: $settings.statusBarMetric) {
                    Text("CPU").tag("cpu")
                    Text("GPU").tag("gpu")
                    Text("PWR").tag("pwr")
                    Text("MEM").tag("memory")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Menu Bar")
            }

            Section {
                Picker("Refresh:", selection: $settings.refreshInterval) {
                    Text("1s").tag(1)
                    Text("2s").tag(2)
                    Text("3s").tag(3)
                    Text("5s").tag(5)
                }
                .pickerStyle(.segmented)

                Toggle("Launch at Login", isOn: loginBinding)
            } header: {
                Text("General")
            }

            Section {
                Button("Apply") {
                    restartAction()
                }
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.return)
            }
        }
        .formStyle(.grouped)
        .frame(width: 300)
        .fixedSize()
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
