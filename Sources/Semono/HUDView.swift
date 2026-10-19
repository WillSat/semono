import SwiftUI

struct HUDView: View {
    @ObservedObject var metrics: MetricsCollector
    @ObservedObject var settings = SettingsStore.shared

    var body: some View {
        HStack(spacing: 0) {
            if settings.showComputeColumn {
                VStack(spacing: 0) {
                    valCell(label: "CPU", usage: metrics.cpuUsage)
                    valCell(label: "GPU", usage: metrics.gpuUsage)
                    MetricCell(label: "PWR", value: optionalValue(metrics.powerUsage.map(MetricFormat.power), width: 4),
                               color: metrics.powerUsage == nil ? missingColor : valueColor)
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
                               color: metrics.swapBytes == nil ? missingColor : ColorScale.color(for: metrics.swapRatio ?? 0, light: isLight))
                }
            }

            if settings.showMemoryColumn && (settings.showStorageColumn || settings.showNetworkColumn) {
                divider
            }

            if settings.showStorageColumn {
                VStack(spacing: 0) {
                    MetricCell(label: "DR", value: optionalValue(metrics.diskReadSpeed.map(MetricFormat.speed), width: 5),
                               color: metrics.diskReadSpeed == nil ? missingColor : valueColor)
                    MetricCell(label: "DW", value: optionalValue(metrics.diskWriteSpeed.map(MetricFormat.speed), width: 5),
                               color: metrics.diskWriteSpeed == nil ? missingColor : valueColor)
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
                .fill(backgroundFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(isLight ? Color.black.opacity(0.10) : Color.clear, lineWidth: 0.5)
                }
        )
        .fixedSize()
    }

    // MARK: - Dimensions

    private var theme: HUDTheme { HUDTheme(rawValue: settings.hudTheme) ?? .dark }
    private var isLight: Bool { theme == .light }

    private var labelColor: Color { isLight ? .black.opacity(0.58) : .white.opacity(0.4) }
    private var valueColor: Color { isLight ? .black.opacity(0.86) : .white.opacity(0.85) }
    private var secondaryValueColor: Color { isLight ? .black.opacity(0.68) : .white.opacity(0.7) }
    private var missingColor: Color { isLight ? .black.opacity(0.35) : .white.opacity(0.4) }
    private var backgroundFill: Color {
        isLight ? .white.opacity(settings.backgroundOpacity) : .black.opacity(settings.backgroundOpacity)
    }
    private var dividerColor: Color { isLight ? .black.opacity(0.14) : .white.opacity(0.12) }
    private var barTrackColor: Color { isLight ? .black.opacity(0.16) : .gray.opacity(0.35) }
    private var arrowColor: Color {
        isLight
            ? Color(red: 0.35, green: 0.20, blue: 0.62)
            : Color(red: 0.70, green: 0.55, blue: 0.92)
    }

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
            let color = ColorScale.color(for: usage, light: isLight)
            if settings.useBlockDisplay {
                BarCell(label: label, ratio: usage, color: color)
            } else {
                MetricCell(label: label, value: fmtPct(usage), color: color)
            }
        } else {
            MetricCell(label: label, value: MetricFormat.dash(4), color: missingColor)
        }
    }

    /// PRS is a three-state kernel signal, not a percentage. Show a
    /// right-aligned `#N` / `#W` / `#C` tag, coloured by level, instead of a
    /// block progress bar whose height implied a granularity macOS does not
    /// provide.
    @ViewBuilder
    private var pressureCell: some View {
        HStack(spacing: 0) {
            Text("PRS")
                .font(.custom(currentFont, size: labelFontSz))
                .foregroundColor(labelColor)
            Spacer(minLength: minSpacer)
            if let level = metrics.memoryPressureLevel {
                Text("#\(MemoryPressure.abbreviation(for: level))")
                    .font(.custom(currentFont, size: valueFontSz))
                    .foregroundColor(ColorScale.color(forPressureLevel: level, light: isLight))
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                Text(MetricFormat.dash(4))
                    .font(.custom(currentFont, size: valueFontSz))
                    .foregroundColor(missingColor)
                    .lineLimit(1)
            }
        }
        .frame(height: cellHeight)
    }

    @ViewBuilder
    private var thermalCell: some View {
        if let level = metrics.thermalState {
            BarCell(label: "THM", ratio: levelRatio(level),
                    color: ColorScale.color(forLevel: level, light: isLight))
        } else {
            MetricCell(label: "THM", value: MetricFormat.dash(4), color: missingColor)
        }
    }

    private func optionalValue(_ value: String?, width: Int) -> String {
        value ?? MetricFormat.dash(width)
    }

    private func MetricCell(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 0) {
            Text(label)
                .font(.custom(currentFont, size: labelFontSz))
                .foregroundColor(labelColor)
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
                .foregroundColor(labelColor)
            Spacer(minLength: minSpacer)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(barTrackColor)
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
                        .foregroundColor(labelColor)
                    Spacer(minLength: minSpacer)
                    if let rssi = metrics.wifiRSSI {
                        Text(String(format: "%3d", rssi))
                            .font(.custom(currentFont, size: valueFontSz))
                            .foregroundColor(ColorScale.color(forRSSI: rssi, light: isLight))
                            .monospacedDigit()
                    } else {
                        // rssiValue() == 0 means "unavailable", not 0 dBm.
                        Text("  \u{2014}")
                            .font(.custom(currentFont, size: valueFontSz))
                            .foregroundColor(missingColor)
                    }
                }
                .frame(height: cellHeight)
            } else {
                Text(type)
                    .font(.custom(currentFont, size: valueFontSz))
                    .foregroundColor(secondaryValueColor)
                    .frame(height: cellHeight)
            }
        } else {
            Text("\u{2014}")
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(missingColor)
                .frame(height: cellHeight)
        }
    }

    private func speedCell(arrow: String, speed: Double?) -> some View {
        HStack(spacing: 0) {
            Text(arrow)
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(arrowColor)
            Spacer(minLength: minSpacer)
            Text(speed.map(MetricFormat.speed) ?? MetricFormat.dash(5))
                .font(.custom(currentFont, size: valueFontSz))
                .foregroundColor(speed == nil ? missingColor : valueColor)
                .monospacedDigit()
                .lineLimit(1)
        }
        .frame(height: cellHeight)
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(width: 1)
            .padding(.vertical, 2)
            .padding(.horizontal, 3)
    }

    private func fmtPct(_ v: Double) -> String { String(format: "%3d%%", Int(v * 100)) }
    /// 0..3 level to a 0..1 bar ratio; level 0 renders as an empty bar.
    private func levelRatio(_ level: Int) -> Double { Double(level) / 3.0 }
}
