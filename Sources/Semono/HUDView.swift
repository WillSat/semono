import SwiftUI

struct HUDView: View {
    @ObservedObject var metrics: MetricsCollector
    @ObservedObject var settings = SettingsStore.shared
    let onDoubleClick: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if settings.showComputeColumn {
                VStack(spacing: 0) {
                    valCell(label: "CPU", usage: metrics.cpuUsage,
                            color: ColorScale.color(for: metrics.cpuUsage))
                    valCell(label: "GPU", usage: metrics.gpuUsage,
                            color: ColorScale.color(for: metrics.gpuUsage))
                    MetricCell(label: "PWR", value: fmtPwr(metrics.powerUsage),
                               color: .white.opacity(0.85))
                }
            }

            if settings.showComputeColumn && (settings.showMemoryColumn || settings.showStorageColumn || settings.showNetworkColumn) {
                divider
            }

            if settings.showMemoryColumn {
                VStack(spacing: 0) {
                    valCell(label: "MEM", usage: metrics.memoryUsage,
                            color: ColorScale.color(for: metrics.memoryUsage))
                    BarCell(label: "PRS", ratio: levelRatio(metrics.memoryPressureLevel),
                            color: ColorScale.color(forLevel: metrics.memoryPressureLevel))
                    MetricCell(label: "SWAP", value: fmtSwap(metrics.swapBytes),
                               color: ColorScale.color(for: metrics.swapRatio))
                }
            }

            if settings.showMemoryColumn && (settings.showStorageColumn || settings.showNetworkColumn) {
                divider
            }

            if settings.showStorageColumn {
                VStack(spacing: 0) {
                    MetricCell(label: "DR", value: fmtSpeed(metrics.diskReadSpeed),
                               color: .white.opacity(0.85))
                    MetricCell(label: "DW", value: fmtSpeed(metrics.diskWriteSpeed),
                               color: .white.opacity(0.85))
                    BarCell(label: "THM", ratio: levelRatio(metrics.thermalState),
                            color: ColorScale.color(forLevel: metrics.thermalState))
                }
            }

            if settings.showStorageColumn && settings.showNetworkColumn {
                divider
            }

            if settings.showNetworkColumn {
                VStack(spacing: 0) {
                    connCell
                    speedCell(arrow: "\u{2191}", speed: metrics.uploadSpeed)
                    speedCell(arrow: "\u{2193}", speed: metrics.downloadSpeed)
                }
            }
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.black.opacity(settings.backgroundOpacity))
        )
        .fixedSize()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDoubleClick?()
        }
    }

    // MARK: - Dimensions

    private var currentFont: String { settings.fontName }
    private var scale: CGFloat { CGFloat(1.0 + settings.fontScale / 10.0) }
    private var labelFontSz: CGFloat { 8 * scale }
    private var valueFontSz: CGFloat { 11 * scale }
    private var barW: CGFloat { valueFontSz * 3.0 }
    private var barH: CGFloat { valueFontSz * 0.85 }
    private var minSpacer: CGFloat { 4 * scale }

    // MARK: - Cells

    @ViewBuilder
    private func valCell(label: String, usage: Double, color: Color) -> some View {
        if settings.useBlockDisplay {
            BarCell(label: label, ratio: usage, color: color)
        } else {
            MetricCell(label: label, value: fmtPct(usage), color: color)
        }
    }

    private func MetricCell(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.custom(currentFont, size: labelFontSz))
                .foregroundColor(.white.opacity(0.4))
            Spacer(minLength: minSpacer)
            Text(value)
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(color)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: valueFontSz * 1.15)
    }

    private func BarCell(label: String, ratio: Double, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.custom(currentFont, size: labelFontSz))
                .foregroundColor(.white.opacity(0.4))
            Spacer(minLength: minSpacer)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.35))
                Rectangle()
                    .fill(color)
                    .frame(width: max(3, barW * CGFloat(max(0, min(1, ratio)))))
            }
            .frame(width: barW, height: barH)
        }
        .frame(height: valueFontSz * 1.15)
    }

    @ViewBuilder
    private var connCell: some View {
        if metrics.networkType == "WiFi" {
            HStack(spacing: 0) {
                Text(metrics.networkType)
                    .font(.custom(currentFont, size: labelFontSz))
                    .foregroundColor(.white.opacity(0.4))
                Spacer(minLength: minSpacer)
                Text(String(format: "%3d", metrics.wifiRSSI))
                    .font(.custom(currentFont, size: valueFontSz))
                    .foregroundColor(ColorScale.color(forRSSI: metrics.wifiRSSI))
                    .monospacedDigit()
            }
            .frame(height: valueFontSz * 1.15)
        } else {
            Text(metrics.networkType)
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(.white.opacity(0.7))
                .frame(height: valueFontSz * 1.15)
        }
    }

    private func speedCell(arrow: String, speed: Double) -> some View {
        HStack(spacing: 0) {
            Text(arrow)
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(Color(red: 0.70, green: 0.55, blue: 0.92))
            Spacer(minLength: minSpacer)
            Text(fmtSpeed(speed))
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(.white.opacity(0.85))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: valueFontSz * 1.15)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 1)
            .padding(.vertical, 2)
            .padding(.horizontal, 3)
    }

    private func fmtPct(_ v: Double) -> String { String(format: "%3d%%", Int(v * 100)) }
    private func fmtPwr(_ w: Double) -> String { String(format: "%4.1f", w) }
    private func levelRatio(_ level: Int) -> Double { Double(level + 1) / 4.0 }

    private func fmtSwap(_ bytes: UInt64) -> String {
        let raw: String
        if bytes >= 1_000_000_000 {
            raw = String(format: "%.1fG", Double(bytes) / 1_000_000_000)
        } else {
            raw = String(format: "%.0fM", Double(bytes) / 1_000_000)
        }
        return pad(raw, to: 4)
    }

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
}
