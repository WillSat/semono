import SwiftUI

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
                    ForEach(SettingsStore.refreshOptions, id: \.self) { seconds in
                        Text("\(seconds)s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(locale.localized("Refresh:"))
            }
        }
        .onAppear { MetricsHistory.shared.isRecording = true }
        .onDisappear { MetricsHistory.shared.isRecording = false }
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

            // Columns are maintained per-core by MetricsHistory so the charts
            // reuse precomputed series instead of re-mapping the history for
            // every core on every tick.
            if !history.perCoreCPUColumns.isEmpty {
                SectionHeader(locale.localized("Per Core"))
                AdaptiveGrid {
                    ForEach(0..<history.perCoreCPUColumns.count, id: \.self) { i in
                        MetricChart(
                            title: "CPU \(i)",
                            icon: nil,
                            unit: "",
                            values: history.perCoreCPUColumns[i],
                            maxY: 1.0,
                            format: { String(format: "%.0f%%", $0 * 100) },
                            compact: true
                        )
                    }
                }
            }

            if !history.perCoreFreqColumns.isEmpty {
                SectionHeader(locale.localized("Frequency") + " (MHz)")
                AdaptiveGrid {
                    ForEach(0..<history.perCoreFreqColumns.count, id: \.self) { i in
                        MetricChart(
                            title: "Freq \(i)",
                            icon: nil,
                            unit: "MHz",
                            values: history.perCoreFreqColumns[i],
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
                    format: MetricFormat.bytesCompact,
                    latestText: history.snapshots.last.map { MetricFormat.bytesCompact(Double($0.swapBytes)) }
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
                format: MetricFormat.speedCompact
            )
            MetricChart(
                title: locale.localized("Disk Write"),
                icon: "arrow.up",
                unit: "",
                values: history.snapshots.map(\.diskWriteSpeed),
                format: MetricFormat.speedCompact
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
                format: MetricFormat.speedCompact
            )
            MetricChart(
                title: locale.localized("Network Up"),
                icon: "arrow.up",
                unit: "",
                values: history.snapshots.map(\.uploadSpeed),
                format: MetricFormat.speedCompact
            )
            MetricChart(
                title: locale.localized("WiFi RSSI"),
                icon: "wifi",
                unit: "dBm",
                values: history.snapshots.map { ColorScale.normalizedRSSI($0.wifiRSSI) },
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

// MARK: - Shared Chart Math

/// Derived values for one chart series, computed once per body evaluation
/// and shared by `PageHero` and `MetricChart` so the two cards cannot drift.
struct ChartMetrics {
    let values: [Double]
    let effectiveMax: Double
    let normPoints: [Double]
    let avg: Double
    let peak: Double

    init(values: [Double], maxY: Double?) {
        self.values = values
        let peak = values.max() ?? 0
        self.peak = peak
        if let maxY {
            effectiveMax = max(maxY, 0.001)
        } else {
            effectiveMax = max(peak * 1.08, 0.001)
        }
        let maxValue = effectiveMax
        normPoints = values.map { min(1.0, max(0, $0 / maxValue)) }
        avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    var latestColor: Color {
        guard let last = values.last else { return .secondary }
        return ColorScale.color(for: min(1.0, max(0, last / effectiveMax)))
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

    var body: some View {
        let m = ChartMetrics(values: values, maxY: maxY)
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
                    .foregroundStyle(m.latestColor)
                    .monospacedDigit()
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
            }

            if m.normPoints.count > 1 {
                Sparkline(values: m.normPoints, color: m.latestColor, height: 84)
            } else {
                Color.clear.frame(height: 84)
            }

            if showStats && values.count > 1 {
                stats(m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.fill.quaternary)
        )
    }

    private func stats(_ m: ChartMetrics) -> some View {
        HStack(spacing: 0) {
            Text("AVG \(format(m.avg))")
            Text("  \u{00B7}  MAX \(format(m.peak))")
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

    var body: some View {
        let m = ChartMetrics(values: values, maxY: maxY)
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            header(color: m.latestColor)
            if m.normPoints.count > 1 {
                Sparkline(
                    values: m.normPoints,
                    color: m.latestColor,
                    height: compact ? 48 : 84,
                    lineWidth: compact ? 1.5 : 2
                )
            } else {
                Color.clear.frame(height: compact ? 48 : 84)
            }
            if showStats && !compact && values.count > 1 {
                stats(m)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 14)
        .background(
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .fill(.fill.quaternary)
        )
    }

    private func header(color: Color) -> some View {
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
                    .foregroundStyle(color)
                    .lineLimit(1)
            } else if let last = values.last {
                Text(format(last))
                    .font(
                        compact
                            ? .system(.subheadline, design: .rounded).weight(.semibold)
                            : .system(.title3, design: .rounded).weight(.semibold)
                    )
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if !unit.isEmpty {
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func stats(_ m: ChartMetrics) -> some View {
        HStack(spacing: 0) {
            Text("AVG \(format(m.avg))")
            Text("  \u{00B7}  MAX \(format(m.peak))")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .monospacedDigit()
    }
}

// MARK: - Sparkline

/// Lightweight self-drawn sparkline — a smooth polyline with a soft gradient
/// fill. Replaces Swift Charts: no display-list machinery, no per-mark
/// tracking areas, so per-tick redraws cost a fraction of a Chart's.
private struct Sparkline: View {
    let values: [Double]
    let color: Color
    let height: CGFloat
    var lineWidth: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let line = Self.linePath(Self.points(values: values, width: w, height: h))
            ZStack {
                Self.areaPath(area: line, width: w, height: h).fill(
                    LinearGradient(
                        colors: [color.opacity(0.28), color.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                line.stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(height: height)
    }

    private static func areaPath(area line: Path, width: CGFloat, height: CGFloat) -> Path {
        var area = line
        area.addLine(to: CGPoint(x: width, y: height))
        area.addLine(to: CGPoint(x: 0, y: height))
        area.closeSubpath()
        return area
    }

    private static func points(values: [Double], width: CGFloat, height: CGFloat) -> [CGPoint] {
        guard values.count > 1, width > 0, height > 0 else { return [] }
        let stepX = width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            CGPoint(
                x: CGFloat(idx) * stepX,
                y: height - CGFloat(max(0, min(1, v))) * height
            )
        }
    }

    /// Smooth curve through the points: quadratic beziers via midpoints,
    /// approximating the monotone interpolation the chart previously used.
    private static func linePath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard let first = pts.first else { return path }
        path.move(to: first)
        guard pts.count > 2 else {
            if pts.count == 2 { path.addLine(to: pts[1]) }
            return path
        }
        for i in 1..<(pts.count - 1) {
            let mid = CGPoint(
                x: (pts[i].x + pts[i + 1].x) / 2,
                y: (pts[i].y + pts[i + 1].y) / 2
            )
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
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
