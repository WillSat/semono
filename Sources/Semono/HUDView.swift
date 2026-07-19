import SwiftUI

private let fontName = "DepartureMono-Regular"

struct HUDView: View {
    @ObservedObject var metrics: MetricsCollector
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                MetricRow(label: "CPU", value: fmtPct(metrics.cpuUsage),
                          color: ColorScale.color(for: metrics.cpuUsage))
                MetricRow(label: "MEM", value: fmtPct(metrics.memoryUsage),
                          color: ColorScale.color(for: metrics.memoryUsage))
                MetricRow(label: "PWR", value: fmtPwr(metrics.powerUsage),
                          color: .white.opacity(0.85))
            }

            divider

            VStack(spacing: 0) {
                connRow
                speedRow(arrow: "↑", speed: metrics.uploadSpeed)
                speedRow(arrow: "↓", speed: metrics.downloadSpeed)
            }
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
    }

    private var divider: some View {
        Color.white.opacity(0.1)
            .frame(width: 1)
            .padding(.vertical, 2)
            .padding(.horizontal, 3)
    }

    @ViewBuilder
    private var connRow: some View {
        if metrics.networkType == "WiFi" {
            HStack(spacing: 1) {
                Text(metrics.networkType)
                    .font(.custom(fontName, size: 8))
                    .foregroundColor(.white.opacity(0.4))
                Text(String(format: "%3d", metrics.wifiRSSI))
                    .font(.custom(fontName, size: 11))
                    .foregroundColor(ColorScale.color(forRSSI: metrics.wifiRSSI))
                    .monospacedDigit()
            }
        } else {
            Text(metrics.networkType)
                .font(.custom(fontName, size: 11))
                .foregroundColor(.white.opacity(0.7))
        }
    }

    private func fmtPct(_ v: Double) -> String { String(format: "%3d%%", Int(v * 100)) }
    private func fmtPwr(_ w: Double) -> String { String(format: "%4.1f", w) }

    private func fmtSpeed(_ bytesPerSec: Double) -> String {
        let raw: String
        guard bytesPerSec >= 0 else { return pad("0B", to: 5) }
        if bytesPerSec >= 1_000_000 {
            raw = String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 10_000 {
            raw = String(format: "%dK", Int(bytesPerSec / 1_000))
        } else if bytesPerSec >= 1_000 {
            raw = String(format: "%.1fK", bytesPerSec / 1_000)
        } else {
            raw = String(format: "%dB", Int(bytesPerSec))
        }
        return pad(raw, to: 5)
    }

    private func pad(_ s: String, to width: Int) -> String {
        if s.count >= width { return s }
        return String(repeating: " ", count: width - s.count) + s
    }

    private func speedRow(arrow: String, speed: Double) -> some View {
        HStack(spacing: 1) {
            Text(arrow)
                .font(.custom(fontName, size: 11))
                .foregroundColor(Color(red: 0.70, green: 0.55, blue: 0.92))
            Text(fmtSpeed(speed))
                .font(.custom(fontName, size: 11))
                .foregroundColor(.white.opacity(0.85))
                .monospacedDigit()
        }
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 1) {
            Text(label)
                .font(.custom(fontName, size: 8))
                .foregroundColor(.white.opacity(0.4))
            Text(value)
                .font(.custom(fontName, size: 11))
                .foregroundColor(color)
                .monospacedDigit()
        }
    }
}
