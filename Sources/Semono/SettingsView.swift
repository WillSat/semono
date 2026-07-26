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

                Toggle("Show in Fullscreen", isOn: $settings.showInFullscreen)

                Picker("Font:", selection: $settings.fontName) {
                    ForEach(SettingsStore.availableFonts, id: \.name) { f in
                        Text(f.label).tag(f.name)
                    }
                }

                Picker("Status Bar:", selection: $settings.statusBarMetric) {
                    Text("CPU").tag("cpu")
                    Text("Memory").tag("memory")
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Display")
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
                Text("Behavior")
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
