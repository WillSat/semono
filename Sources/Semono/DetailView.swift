import SwiftUI
import Charts

enum DetailPage: String, CaseIterable, Hashable, Identifiable {
    case cpu, gpu, memory, storage, network, other

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "square.3.layers.3d"
        case .memory: "memorychip"
        case .storage: "internaldrive"
        case .network: "network"
        case .other: "thermometer.medium"
        }
    }

    var titleKey: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .memory: "Memory"
        case .storage: "Storage"
        case .network: "Network"
        case .other: "Other"
        }
    }
}

/// Monitoring window on the macOS 26/27 design language.
///
/// Liquid Glass belongs to the navigation layer only: the sidebar and
/// toolbar are system glass. Scrolling content stays on quiet system
/// fills — never glass on glass.
struct DetailView: View {
    @ObservedObject var history = MetricsHistory.shared
    let metrics: MetricsCollector
    @ObservedObject var settings = SettingsStore.shared
    @ObservedObject var locale = LocaleManager.shared
    @State private var selectedPage: DetailPage = .cpu

    init(metrics: MetricsCollector) {
        self.metrics = metrics
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ScrollView {
                pageContent
                    .id(selectedPage)
                    .transition(.opacity.combined(with: .offset(y: 8)))
                    .padding(16)
            }
            .scrollIndicators(.hidden)
            .animation(.snappy(duration: 0.3), value: selectedPage)
        }
        .navigationTitle(locale.localized(selectedPage.titleKey))
        .tint(ColorScale.accent)
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("", selection: $settings.refreshInterval) {
                    Text("1s").tag(1)
                    Text("2s").tag(2)
                    Text("3s").tag(3)
                    Text("5s").tag(5)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(locale.localized("Refresh:"))
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedPage) {
            ForEach(DetailPage.allCases) { page in
                Label(locale.localized(page.titleKey), systemImage: page.icon)
                    .tag(page)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 165, ideal: 190, max: 240)
    }

    // MARK: - Pages

    @ViewBuilder
    private var pageContent: some View {
        switch selectedPage {
        case .cpu:    cpuPage
        case .gpu:    gpuPage
        case .memory: memoryPage
        case .storage: storagePage
        case .network: networkPage
        case .other:  otherPage
        }
    }

    /// CPU: hero overview + per-core usage and frequency grids.
    private var cpuPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHero(
                icon: "cpu",
                title: locale.localized("CPU Usage"),
                unit: "",
                values: history.snapshots.map(\.cpuUsage),
                maxY: 1.0,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            if let last = history.snapshots.last, !last.perCoreCPU.isEmpty {
                SectionHeader(locale.localized("Per Core"))
                AdaptiveGrid {
                    ForEach(0..<last.perCoreCPU.count, id: \.self) { i in
                        MetricChart(
                            title: "CPU \(i)",
                            icon: nil,
                            unit: "",
                            values: history.snapshots.map { s in
                                s.perCoreCPU.count > i ? s.perCoreCPU[i] : 0
                            },
                            maxY: 1.0,
                            format: { String(format: "%.0f%%", $0 * 100) },
                            compact: true
                        )
                    }
                }
            }

            if let last = history.snapshots.last, !last.perCoreFreqMHz.isEmpty {
                SectionHeader(locale.localized("Frequency") + " (MHz)")
                AdaptiveGrid {
                    ForEach(0..<last.perCoreFreqMHz.count, id: \.self) { i in
                        MetricChart(
                            title: "Freq \(i)",
                            icon: nil,
                            unit: "MHz",
                            values: history.snapshots.map { s in
                                s.perCoreFreqMHz.count > i ? s.perCoreFreqMHz[i] : 0
                            },
                            format: { String(format: "%.0f", $0) },
                            compact: true
                        )
                    }
                }
            }
        }
    }

    /// GPU: hero overview.
    private var gpuPage: some View {
        PageHero(
            icon: "square.3.layers.3d",
            title: locale.localized("GPU Usage"),
            unit: "",
            values: history.snapshots.map(\.gpuUsage),
            maxY: 1.0,
            format: { String(format: "%.0f%%", $0 * 100) }
        )
    }

    /// Memory: hero overview + swap and pressure detail.
    private var memoryPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHero(
                icon: "memorychip",
                title: locale.localized("Memory Usage"),
                unit: "",
                values: history.snapshots.map(\.memoryUsage),
                maxY: 1.0,
                format: { String(format: "%.0f%%", $0 * 100) }
            )

            AdaptiveGrid {
                MetricChart(
                    title: locale.localized("Swap Usage"),
                    icon: "arrow.triangle.2.circlepath",
                    unit: "",
                    values: history.snapshots.map { Double($0.swapBytes) },
                    format: fmtBytesSmall,
                    latestText: history.snapshots.last.map { fmtBytesSmall(Double($0.swapBytes)) }
                )

                MetricChart(
                    title: locale.localized("Memory Pressure"),
                    icon: "gauge",
                    unit: "",
                    values: history.snapshots.map { Double(clampLevel($0.memoryPressureLevel) + 1) / 4.0 },
                    maxY: 1.0,
                    format: { _ in "" },
                    latestText: history.snapshots.last.map {
                        ["N", "M", "H", "C"][clampLevel($0.memoryPressureLevel)]
                    },
                    showStats: false
                )
            }
        }
    }

    /// Storage: read / write throughput.
    private var storagePage: some View {
        AdaptiveGrid {
            MetricChart(
                title: locale.localized("Disk Read"),
                icon: "arrow.down",
                unit: "",
                values: history.snapshots.map(\.diskReadSpeed),
                format: fmtSpeedShort
            )
            MetricChart(
                title: locale.localized("Disk Write"),
                icon: "arrow.up",
                unit: "",
                values: history.snapshots.map(\.diskWriteSpeed),
                format: fmtSpeedShort
            )
        }
    }

    /// Network: down / up throughput and Wi-Fi signal.
    private var networkPage: some View {
        AdaptiveGrid {
            MetricChart(
                title: locale.localized("Network Down"),
                icon: "arrow.down",
                unit: "",
                values: history.snapshots.map(\.downloadSpeed),
                format: fmtSpeedShort
            )
            MetricChart(
                title: locale.localized("Network Up"),
                icon: "arrow.up",
                unit: "",
                values: history.snapshots.map(\.uploadSpeed),
                format: fmtSpeedShort
            )
            MetricChart(
                title: locale.localized("WiFi RSSI"),
                icon: "wifi",
                unit: "dBm",
                values: history.snapshots.map { rssiNorm($0.wifiRSSI) },
                maxY: 1.0,
                format: { _ in "" },
                latestText: history.snapshots.last.map { $0.wifiRSSI == 0 ? "\u{2014}" : "\($0.wifiRSSI)" },
                showStats: false
            )
        }
    }

    /// Other: thermal state hero + power draw detail.
    private var otherPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHero(
                icon: "thermometer.medium",
                title: locale.localized("Thermal State"),
                unit: "",
                values: history.snapshots.map { Double(clampLevel($0.thermalState) + 1) / 4.0 },
                maxY: 1.0,
                format: { _ in "" },
                latestText: history.snapshots.last.map {
                    [locale.localized("Nominal"), locale.localized("Moderate"),
                     locale.localized("Heavy"), locale.localized("Critical")][clampLevel($0.thermalState)]
                },
                showStats: false
            )

            AdaptiveGrid {
                MetricChart(
                    title: locale.localized("Power Draw"),
                    icon: "bolt.fill",
                    unit: "W",
                    values: history.snapshots.map(\.powerUsage),
                    format: { String(format: "%.1f", $0) }
                )
            }
        }
    }

    // MARK: - Helpers

    private func clampLevel(_ level: Int) -> Int {
        min(3, max(0, level))
    }

    private func rssiNorm(_ rssi: Int) -> Double {
        rssi == 0 ? 0 : Double(max(30, min(90, abs(rssi))) - 30) / 60.0
    }

    private func fmtBytesSmall(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1fG", bytes / 1_000_000_000)
        } else {
            return String(format: "%.0fM", bytes / 1_000_000)
        }
    }

    private func fmtSpeedShort(_ bytesPerSec: Double) -> String {
        guard bytesPerSec >= 0 else { return "0B" }
        if bytesPerSec >= 1_000_000 {
            return String(format: "%.1fM", bytesPerSec / 1_000_000)
        } else if bytesPerSec >= 1_000 {
            return String(format: "%.0fK", bytesPerSec / 1_000)
        } else {
            return String(format: "%.0fB", bytesPerSec)
        }
    }
}

// MARK: - Section Header

/// Quiet section divider for scrolling content.
struct SectionHeader: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }
}

// MARK: - Page Hero

/// Large overview card for a page's primary metric: icon chip, big live
/// value, history sparkline, AVG/MAX. Content-layer fill — no glass in
/// scrolling content.
struct PageHero: View {
    let icon: String
    let title: String
    let unit: String
    let values: [Double]
    var maxY: Double? = nil
    var format: (Double) -> String = { String(format: "%.1f", $0) }
    var latestText: String? = nil
    var showStats: Bool = true

    private var effectiveMax: Double {
        if let maxY { return max(maxY, 0.001) }
        let peak = values.max() ?? 0
        return max(peak * 1.08, 0.001)
    }

    private var normPoints: [Double] {
        values.map { min(1.0, max(0, $0 / effectiveMax)) }
    }

    private var latestColor: Color {
        guard let last = values.last else { return .secondary }
        return ColorScale.color(for: min(1.0, max(0, last / effectiveMax)))
    }

    private var avg: Double {
        values.reduce(0, +) / Double(values.count)
    }

    private var peak: Double {
        values.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 26, height: 26)
                    .background(.tint.opacity(0.14), in: .rect(cornerRadius: 7))
                Text(title)
                    .font(.headline)
                Spacer(minLength: 4)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latestText ?? (values.last.map(format) ?? "\u{2014}"))
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(latestColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: values.last)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }

            if normPoints.count > 1 {
                Sparkline(values: normPoints, color: latestColor, height: 84)
            } else {
                Color.clear.frame(height: 84)
            }

            if showStats && values.count > 1 {
                stats
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.fill.quaternary)
        )
    }

    private var stats: some View {
        HStack(spacing: 0) {
            Text("AVG \(format(avg))")
            Text("  \u{00B7}  MAX \(format(peak))")
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Metric Chart

/// A single-metric card: icon + title, live value, sparkline, AVG/MAX stats.
/// Values are raw; the chart auto-scales to `maxY` (or to the data peak).
/// Cards use a quiet system fill — the Liquid Glass layer belongs to the
/// window chrome (sidebar/toolbar), not to scrolling content.
struct MetricChart: View {
    let title: String
    let icon: String?
    let unit: String
    let values: [Double]
    var maxY: Double? = nil
    var format: (Double) -> String = { String(format: "%.1f", $0) }
    var latestText: String? = nil
    var showStats: Bool = true
    var compact: Bool = false

    private var effectiveMax: Double {
        if let maxY { return max(maxY, 0.001) }
        let peak = values.max() ?? 0
        return max(peak * 1.08, 0.001)
    }

    private var normPoints: [Double] {
        values.map { min(1.0, max(0, $0 / effectiveMax)) }
    }

    private var latestColor: Color {
        guard let last = values.last else { return .secondary }
        return ColorScale.color(for: min(1.0, max(0, last / effectiveMax)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            header
            if normPoints.count > 1 {
                Sparkline(
                    values: normPoints,
                    color: latestColor,
                    height: compact ? 48 : 84,
                    lineWidth: compact ? 1.5 : 2
                )
            } else {
                Color.clear.frame(height: compact ? 48 : 84)
            }
            if showStats && !compact && values.count > 1 {
                stats
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .fill(.fill.quaternary)
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let latestText {
                Text(latestText)
                    .font(compact ? .caption.monospaced().weight(.semibold) : .callout.monospaced().weight(.semibold))
                    .foregroundStyle(latestColor)
                    .lineLimit(1)
            } else if let last = values.last {
                Text(format(last))
                    .font(
                        compact
                            ? .system(.subheadline, design: .rounded).weight(.semibold)
                            : .system(.title3, design: .rounded).weight(.semibold)
                    )
                    .foregroundStyle(latestColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.35), value: last)
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var stats: some View {
        HStack(spacing: 0) {
            Text("AVG \(format(avg))")
            Text("  \u{00B7}  MAX \(format(peak))")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }

    private var avg: Double {
        values.reduce(0, +) / Double(values.count)
    }

    private var peak: Double {
        values.max() ?? 0
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Double]
    let color: Color
    let height: CGFloat
    var lineWidth: CGFloat = 2

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                AreaMark(
                    x: .value("Index", idx),
                    y: .value("Value", v)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Index", idx),
                    y: .value("Value", v)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...1)
        .frame(height: height)
    }
}

// MARK: - Adaptive Grid

struct AdaptiveGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 280), spacing: 12)],
            spacing: 12
        ) {
            content()
        }
    }
}
