import SwiftUI

private let fontName = "DepartureMono-Regular"

struct HUDView: View {
    @ObservedObject var metrics: MetricsCollector
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        VStack(spacing: 0) {
            MetricRow(
                label: "CPU",
                value: String(format: "%3d%%", Int(metrics.cpuUsage * 100)),
                valueColor: ColorScale.color(for: metrics.cpuUsage),
                arrow: "↑",
                speed: formatSpeed(metrics.uploadSpeed, maxWidth: 5),
                speedColor: ColorScale.color(for: min(metrics.uploadSpeed / 5_000_000, 1))
            )
            MetricRow(
                label: "MEM",
                value: String(format: "%3d%%", Int(metrics.memoryUsage * 100)),
                valueColor: ColorScale.color(for: metrics.memoryUsage),
                arrow: "↓",
                speed: formatSpeed(metrics.downloadSpeed, maxWidth: 5),
                speedColor: ColorScale.color(for: min(metrics.downloadSpeed / 5_000_000, 1))
            )
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black.opacity(settings.backgroundOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .fixedSize()
        .drawingGroup()
    }

    private func formatSpeed(_ bytesPerSec: Double, maxWidth: Int) -> String {
        let raw: String
        guard bytesPerSec >= 0 else { return pad("0B", to: maxWidth) }
        if bytesPerSec >= 1_000_000 {
            raw = String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 10_000 {
            raw = String(format: "%dK", Int(bytesPerSec / 1_000))
        } else if bytesPerSec >= 1_000 {
            raw = String(format: "%.1fK", bytesPerSec / 1_000)
        } else {
            raw = String(format: "%dB", Int(bytesPerSec))
        }
        return pad(raw, to: maxWidth)
    }

    private func pad(_ s: String, to width: Int) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String
    let valueColor: Color
    let arrow: String
    let speed: String
    let speedColor: Color

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 1) {
                Text(label)
                    .font(.custom(fontName, size: 8))
                    .foregroundColor(.white.opacity(0.4))
                Text(value)
                    .font(.custom(fontName, size: 11))
                    .foregroundColor(valueColor)
                    .monospacedDigit()
            }

            Color.white.opacity(0.1)
                .frame(width: 1)
                .padding(.horizontal, 3)

            HStack(spacing: 1) {
                Text(arrow)
                    .font(.custom(fontName, size: 11))
                    .foregroundColor(speedColor)
                Text(speed)
                    .font(.custom(fontName, size: 11))
                    .foregroundColor(.white.opacity(0.85))
                    .monospacedDigit()
            }
        }
    }
}
