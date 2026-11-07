import SwiftUI

struct ScreenCornersToolView: View {
    @ObservedObject private var locale = LocaleManager.shared
    @AppStorage(ScreenCornerSettings.enabledKey) private var enabled = false
    @AppStorage(ScreenCornerSettings.modeKey) private var modeRawValue =
        ScreenCornerMode.matchWindows.rawValue
    @AppStorage(ScreenCornerSettings.radiusKey) private var radius =
        ScreenCornerSettings.defaultRadius
    @AppStorage(ScreenCornerSettings.curvatureKey) private var curvature =
        ScreenCornerSettings.defaultCurvature
    @AppStorage(ScreenCornerSettings.showInFullScreenKey) private var showInFullScreen = false

    private var mode: ScreenCornerMode {
        ScreenCornerMode(rawValue: modeRawValue) ?? .matchWindows
    }

    private func t(_ key: String) -> String { locale.localized(key) }

    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "rectangle.roundedbottom")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: .rect(cornerRadius: 8)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Enable Screen Corners"))
                        .font(.headline)
                    Text(t("Rounds the bottom two corners of the built-in display, above all windows."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: 8) {
                Text(t("Mode"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("", selection: $modeRawValue) {
                    ForEach(ScreenCornerMode.allCases, id: \.rawValue) { mode in
                        Text(t(mode.titleKey)).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if mode == .matchWindows {
                    Text(t("Uses the macOS 27 window corner radius and curvature."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(
                        format: "%.0f pt · %.1f",
                        ScreenCornerSettings.windowRadius,
                        ScreenCornerSettings.windowCurvature
                    ))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        sliderRow(
                            title: t("Corner Radius"),
                            value: $radius,
                            range: ScreenCornerSettings.radiusRange,
                            step: 1,
                            display: "\(Int(radius.rounded())) pt"
                        )

                        sliderRow(
                            title: t("Curvature"),
                            value: $curvature,
                            range: ScreenCornerSettings.curvatureRange,
                            step: 0.1,
                            display: String(format: "%.1f", curvature),
                            caption: t("Higher values are squarer; lower values are rounder.")
                        )
                    }
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.5)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text(t("Only affects the built-in display."))
            }
            .font(.caption)
            .foregroundStyle(.tertiary)

            Divider().opacity(0.5)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("Show in Full Screen"))
                        .font(.callout.weight(.medium))
                    Text(t("When off, corners are hidden in full screen."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Toggle("", isOn: $showInFullScreen)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        }
        .onAppear {
            ScreenCornerOverlayController.shared.start()
            ScreenCornerOverlayController.shared.refresh()
        }
        .onChange(of: enabled) { _, _ in syncOverlay() }
        .onChange(of: modeRawValue) { _, _ in syncOverlay() }
        .onChange(of: radius) { _, _ in syncOverlay() }
        .onChange(of: curvature) { _, _ in syncOverlay() }
        .onChange(of: showInFullScreen) { _, _ in syncOverlay() }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        display: String,
        caption: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.callout)
                Spacer()
                Text(display)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(value: value, in: range, step: step)

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func syncOverlay() {
        ScreenCornerOverlayController.shared.refresh()
    }
}
