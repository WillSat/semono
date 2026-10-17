import SwiftUI

struct HUDView: View {
    @ObservedObject var metrics: MetricsCollector
    @ObservedObject var settings = SettingsStore.shared
    let onDoubleClick: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            if settings.showComputeColumn {
                VStack(spacing: 0) {
                    valCell(label: "CPU", usage: metrics.cpuUsage)
                    valCell(label: "GPU", usage: metrics.gpuUsage)
                    MetricCell(label: "PWR", value: optionalValue(metrics.powerUsage.map(MetricFormat.power), width: 4),
                               color: metrics.powerUsage == nil ? .white.opacity(0.4) : .white.opacity(0.85))
                }
            }

            if settings.showComputeColumn && (settings.showMemoryColumn || settings.showStorageColumn || settings.showNetworkColumn) {
                divider
            }

            if settings.showMemoryColumn {
                VStack(spacing: 0) {
                    valCell(label: "MEM", usage: metrics.memoryUsage)
                    pressureCell
                    MetricCell(label: "SWAP", value: optionalValue(metrics.swapBytes.map(MetricFormat.swap), width: 4),
                               color: metrics.swapBytes == nil ? .white.opacity(0.4) : ColorScale.color(for: metrics.swapRatio ?? 0))
                }
            }

            if settings.showMemoryColumn && (settings.showStorageColumn || settings.showNetworkColumn) {
                divider
            }

            if settings.showStorageColumn {
                VStack(spacing: 0) {
                    MetricCell(label: "DR", value: optionalValue(metrics.diskReadSpeed.map(MetricFormat.speed), width: 5),
                               color: metrics.diskReadSpeed == nil ? .white.opacity(0.4) : .white.opacity(0.85))
                    MetricCell(label: "DW", value: optionalValue(metrics.diskWriteSpeed.map(MetricFormat.speed), width: 5),
                               color: metrics.diskWriteSpeed == nil ? .white.opacity(0.4) : .white.opacity(0.85))
                    thermalCell
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
    private var barW: CGFloat { valueFontSz * Self.barWidthFactor }
    private var barH: CGFloat { valueFontSz * Self.barHeightFactor }
    private var cellHeight: CGFloat { valueFontSz * Self.cellHeightFactor }
    private var minSpacer: CGFloat { 4 * scale }

    // Geometry factors tuned against the pixel-art HUD layout.
    private static let barWidthFactor: CGFloat = 3.0
    private static let barHeightFactor: CGFloat = 0.85
    private static let cellHeightFactor: CGFloat = 1.15

    // MARK: - Cells

    @ViewBuilder
    private func valCell(label: String, usage: Double?) -> some View {
        if let usage {
            let color = ColorScale.color(for: usage)
            if settings.useBlockDisplay {
                BarCell(label: label, ratio: usage, color: color)
            } else {
                MetricCell(label: label, value: fmtPct(usage), color: color)
            }
        } else {
            MetricCell(label: label, value: MetricFormat.dash(4), color: .white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var pressureCell: some View {
        if let level = metrics.memoryPressureLevel {
            BarCell(label: "PRS", ratio: levelRatio(level),
                    color: ColorScale.color(forLevel: level))
        } else {
            MetricCell(label: "PRS", value: MetricFormat.dash(4), color: .white.opacity(0.4))
        }
    }

    @ViewBuilder
    private var thermalCell: some View {
        if let level = metrics.thermalState {
            BarCell(label: "THM", ratio: levelRatio(level),
                    color: ColorScale.color(forLevel: level))
        } else {
            MetricCell(label: "THM", value: MetricFormat.dash(4), color: .white.opacity(0.4))
        }
    }

    private func optionalValue(_ value: String?, width: Int) -> String {
        value ?? MetricFormat.dash(width)
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
        .frame(height: cellHeight)
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
        .frame(height: cellHeight)
    }

    @ViewBuilder
    private var connCell: some View {
        if let type = metrics.networkType {
            if type == "WiFi" {
                HStack(spacing: 0) {
                    Text(type)
                        .font(.custom(currentFont, size: labelFontSz))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer(minLength: minSpacer)
                    if let rssi = metrics.wifiRSSI {
                        Text(String(format: "%3d", rssi))
                            .font(.custom(currentFont, size: valueFontSz))
                            .foregroundColor(ColorScale.color(forRSSI: rssi))
                            .monospacedDigit()
                    } else {
                        // rssiValue() == 0 means "unavailable", not 0 dBm.
                        Text("  \u{2014}")
                            .font(.custom(currentFont, size: valueFontSz))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(height: cellHeight)
            } else {
                Text(type)
                    .font(.custom(currentFont, size: valueFontSz))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(height: cellHeight)
            }
        } else {
            Text("\u{2014}")
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(.white.opacity(0.4))
                .frame(height: cellHeight)
        }
    }

    private func speedCell(arrow: String, speed: Double?) -> some View {
        HStack(spacing: 0) {
            Text(arrow)
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(Color(red: 0.70, green: 0.55, blue: 0.92))
            Spacer(minLength: minSpacer)
            Text(speed.map(MetricFormat.speed) ?? MetricFormat.dash(5))
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(speed == nil ? .white.opacity(0.4) : .white.opacity(0.85))
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: cellHeight)
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
    /// 0..3 level to a 0..1 bar ratio; level 0 renders as an empty bar.
    private func levelRatio(_ level: Int) -> Double { Double(level) / 3.0 }
}
