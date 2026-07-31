import SwiftUI

enum DetailPage: String, CaseIterable, Identifiable {
    case cpu, gpu, memory, storage, network, other
    var id: String { rawValue }
}

final class DetailViewState: ObservableObject {
    @Published var selectedPage: DetailPage = .cpu
}

struct DetailView: View {
    @ObservedObject var history = MetricsHistory.shared
    @ObservedObject var metrics: MetricsCollector
    @ObservedObject var locale = LocaleManager.shared
    @ObservedObject private var state = DetailViewState()

    init(metrics: MetricsCollector) {
        self.metrics = metrics
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.selectedPage) {
                Text(locale.localized("CPU")).tag(DetailPage.cpu)
                Text(locale.localized("GPU")).tag(DetailPage.gpu)
                Text(locale.localized("Memory")).tag(DetailPage.memory)
                Text(locale.localized("Storage")).tag(DetailPage.storage)
                Text(locale.localized("Network")).tag(DetailPage.network)
                Text(locale.localized("Other")).tag(DetailPage.other)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            Divider()
                .padding(.horizontal, 10)

            ScrollView(.vertical) {
                pageContent
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.92))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var pageContent: some View {
        switch state.selectedPage {
        case .cpu:    cpuPage
        case .gpu:    gpuPage
        case .memory: memoryPage
        case .storage: storagePage
        case .network: networkPage
        case .other:  otherPage
        }
    }

    // MARK: - CPU Page

    private var cpuPage: some View {
        VStack(spacing: 10) {
            let usagePoints = history.snapshots.map {
                ChartPoint(value: $0.cpuUsage, color: ColorScale.color(for: $0.cpuUsage))
            }
            RichChart(
                title: locale.localized("CPU Usage"),
                unit: "%",
                points: usagePoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { String(format: "%.0f", $0.cpuUsage * 100) }
            )

            if let last = history.snapshots.last, !last.perCoreCPU.isEmpty {
                AdaptiveGrid {
                    ForEach(0..<last.perCoreCPU.count, id: \.self) { i in
                        let pts = history.snapshots.map { s -> ChartPoint in
                            let v = s.perCoreCPU.count > i ? s.perCoreCPU[i] : 0
                            return ChartPoint(value: v, color: ColorScale.color(for: v))
                        }
                        let rawVals = history.snapshots.map { s -> String in
                            let v = s.perCoreCPU.count > i ? s.perCoreCPU[i] : 0
                            return String(format: "%.0f", v * 100)
                        }
                        RichChart(
                            title: "CPU \(i)",
                            unit: "%",
                            points: pts,
                            maxY: 1.0,
                            rawValues: rawVals,
                            small: true
                        )
                    }
                }
            }

            if let last = history.snapshots.last, !last.perCoreFreqMHz.isEmpty {
                SectionLabel(locale.localized("Frequency") + " (MHz)")
                AdaptiveGrid {
                    ForEach(0..<last.perCoreFreqMHz.count, id: \.self) { i in
                        let maxFreq = history.snapshots.compactMap { s in
                            s.perCoreFreqMHz.count > i ? s.perCoreFreqMHz[i] : nil
                        }.max() ?? 4000
                        let cap = max(maxFreq, 1000)
                        let pts = history.snapshots.map { s -> ChartPoint in
                            let v = s.perCoreFreqMHz.count > i ? s.perCoreFreqMHz[i] : 0
                            return ChartPoint(value: v / cap, color: freqColor(v))
                        }
                        let rawVals = history.snapshots.map { s -> String in
                            let v = s.perCoreFreqMHz.count > i ? s.perCoreFreqMHz[i] : 0
                            return String(format: "%.0f", v)
                        }
                        RichChart(
                            title: "Freq \(i)",
                            unit: "MHz",
                            points: pts,
                            maxY: 1.0,
                            rawValues: rawVals,
                            small: true
                        )
                    }
                }
            }
        }
    }

    // MARK: - GPU Page

    private var gpuPage: some View {
        VStack(spacing: 10) {
            let usagePoints = history.snapshots.map {
                ChartPoint(value: $0.gpuUsage, color: ColorScale.color(for: $0.gpuUsage))
            }
            RichChart(
                title: locale.localized("GPU Usage"),
                unit: "%",
                points: usagePoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { String(format: "%.0f", $0.gpuUsage * 100) }
            )
        }
    }

    // MARK: - Memory Page

    private var memoryPage: some View {
        VStack(spacing: 10) {
            let memPoints = history.snapshots.map {
                ChartPoint(value: $0.memoryUsage, color: ColorScale.color(for: $0.memoryUsage))
            }
            RichChart(
                title: locale.localized("Memory Usage"),
                unit: "%",
                points: memPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { String(format: "%.0f", $0.memoryUsage * 100) }
            )

            let swapPoints = history.snapshots.map {
                ChartPoint(value: $0.swapRatio, color: ColorScale.color(for: $0.swapRatio))
            }
            RichChart(
                title: locale.localized("Swap Usage"),
                unit: "GB",
                points: swapPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { fmtBytesSmall($0.swapBytes) },
                rawValueHasUnit: true
            )

            let presPoints = history.snapshots.map {
                ChartPoint(value: Double($0.memoryPressureLevel + 1) / 4.0,
                           color: ColorScale.color(forLevel: $0.memoryPressureLevel))
            }
            RichChart(
                title: locale.localized("Memory Pressure"),
                unit: "",
                points: presPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { ["N", "M", "H", "C"][$0.memoryPressureLevel] }
            )
        }
    }

    // MARK: - Storage Page

    private var storagePage: some View {
        VStack(spacing: 10) {
            let readPoints = history.snapshots.map {
                ChartPoint(value: normSpeed($0.diskReadSpeed, cap: 500_000_000),
                           color: .green)
            }
            RichChart(
                title: locale.localized("Disk Read"),
                unit: "MB/s",
                points: readPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { fmtSpeedShort($0.diskReadSpeed) },
                rawValueHasUnit: true
            )

            let writePoints = history.snapshots.map {
                ChartPoint(value: normSpeed($0.diskWriteSpeed, cap: 500_000_000),
                           color: .orange)
            }
            RichChart(
                title: locale.localized("Disk Write"),
                unit: "MB/s",
                points: writePoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { fmtSpeedShort($0.diskWriteSpeed) },
                rawValueHasUnit: true
            )
        }
    }

    // MARK: - Network Page

    private var networkPage: some View {
        VStack(spacing: 10) {
            let downPoints = history.snapshots.map {
                ChartPoint(value: normSpeed($0.downloadSpeed, cap: 125_000_000),
                           color: Color(red: 0.70, green: 0.55, blue: 0.92))
            }
            RichChart(
                title: locale.localized("Network Down"),
                unit: "MB/s",
                points: downPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { fmtSpeedShort($0.downloadSpeed) },
                rawValueHasUnit: true
            )

            let upPoints = history.snapshots.map {
                ChartPoint(value: normSpeed($0.uploadSpeed, cap: 125_000_000),
                           color: Color(red: 0.70, green: 0.55, blue: 0.92))
            }
            RichChart(
                title: locale.localized("Network Up"),
                unit: "MB/s",
                points: upPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { fmtSpeedShort($0.uploadSpeed) },
                rawValueHasUnit: true
            )

            let rssiPoints = history.snapshots.map {
                let v = Double(max(0, min(60, 60 + ($0.wifiRSSI == 0 ? -60 : $0.wifiRSSI)))) / 60.0
                return ChartPoint(value: v, color: ColorScale.color(forRSSI: $0.wifiRSSI))
            }
            RichChart(
                title: locale.localized("WiFi RSSI"),
                unit: "dBm",
                points: rssiPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { $0.wifiRSSI == 0 ? "-" : String($0.wifiRSSI) }
            )
        }
    }

    // MARK: - Other Page

    private var otherPage: some View {
        VStack(spacing: 10) {
            let thermalPoints = history.snapshots.map {
                ChartPoint(value: Double($0.thermalState + 1) / 4.0,
                           color: ColorScale.color(forLevel: $0.thermalState))
            }
            RichChart(
                title: locale.localized("Thermal State"),
                unit: "",
                points: thermalPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map {
                    [locale.localized("Nominal"), locale.localized("Moderate"),
                     locale.localized("Heavy"), locale.localized("Critical")][$0.thermalState]
                }
            )

            let powerPoints = history.snapshots.map {
                ChartPoint(value: min($0.powerUsage / 60.0, 1.0), color: .orange)
            }
            RichChart(
                title: locale.localized("Power Draw"),
                unit: "W",
                points: powerPoints,
                maxY: 1.0,
                rawValues: history.snapshots.map { String(format: "%.1f", $0.powerUsage) }
            )
        }
    }

    // MARK: - Helpers

    private func normSpeed(_ speed: Double, cap: Double) -> Double {
        guard speed > 0 else { return 0 }
        return min(1.0, speed / cap)
    }

    private func fmtBytesSmall(_ bytes: UInt64) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.1fG", Double(bytes) / 1_000_000_000)
        } else {
            return String(format: "%.0fM", Double(bytes) / 1_000_000)
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

    private func freqColor(_ mhz: Double) -> Color {
        if mhz < 500  { return .gray }
        if mhz < 1500 { return .blue }
        if mhz < 2500 { return .green }
        if mhz < 3500 { return .orange }
        return .red
    }
}

// MARK: - Chart Point

struct ChartPoint {
    let value: Double
    let color: Color
}

// MARK: - Section Label

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.custom("DepartureMono-Regular", size: 10))
            .foregroundColor(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }
}

// MARK: - Rich Chart

struct RichChart: View {
    let title: String
    let unit: String
    let points: [ChartPoint]
    let maxY: Double
    var rawValues: [String]?
    var small: Bool = false
    var rawValueHasUnit: Bool = false

    private var chartHeight: CGFloat { small ? 88 : 144 }
    private var labelSize: CGFloat { small ? 9 : 11 }
    private var gridLines: Int { small ? 2 : 4 }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 0) {
                Text(title)
                    .font(.custom("DepartureMono-Regular", size: labelSize))
                    .foregroundColor(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let values = rawValues, let last = values.last {
                    Text(last)
                        .font(.custom("DepartureMono-Regular", size: labelSize))
                        .foregroundColor(points.last?.color ?? .white)
                        .monospacedDigit()
                    if !rawValueHasUnit, !unit.isEmpty {
                        Text(" " + unit)
                            .font(.custom("DepartureMono-Regular", size: labelSize))
                            .foregroundColor(.white.opacity(0.3))
                    }
                } else if let last = points.last {
                    Text(String(format: "%.0f", last.value * maxY))
                        .font(.custom("DepartureMono-Regular", size: labelSize))
                        .foregroundColor(last.color)
                        .monospacedDigit()
                    if !unit.isEmpty {
                        Text(" " + unit)
                            .font(.custom("DepartureMono-Regular", size: labelSize))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .topLeading) {
                    gridBackground(w: w, h: h)

                    if points.count > 1 {
                        segmentFill(w: w, h: h)
                        segmentLines(w: w, h: h)
                    }
                }
            }
            .frame(height: chartHeight)
        }
        .padding(7)
        .background(Color.white.opacity(0.05))
        .overlay(Rectangle().stroke(Color.white.opacity(0.07), lineWidth: 0.5))
    }

    private func gridBackground(w: CGFloat, h: CGFloat) -> some View {
        Canvas { context, _ in
            for i in 1...gridLines {
                let y = h * CGFloat(i) / CGFloat(gridLines + 1)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
            }

            let vLines = min(6, max(2, points.count / 6))
            for i in 1...vLines {
                let x = w * CGFloat(i) / CGFloat(vLines + 1)
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
                context.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 0.5)
            }
        }
    }

    private func segmentFill(w: CGFloat, h: CGFloat) -> some View {
        Canvas { context, _ in
            let stepX = w / CGFloat(max(points.count - 1, 1))

            for i in 0..<(points.count - 1) {
                let x0 = stepX * CGFloat(i)
                let x1 = stepX * CGFloat(i + 1)
                let y0 = h * CGFloat(1.0 - min(max(0, points[i].value), maxY) / maxY)
                let y1 = h * CGFloat(1.0 - min(max(0, points[i + 1].value), maxY) / maxY)

                var fillPath = Path()
                fillPath.move(to: CGPoint(x: x0, y: y0))
                fillPath.addLine(to: CGPoint(x: x1, y: y1))
                fillPath.addLine(to: CGPoint(x: x1, y: h))
                fillPath.addLine(to: CGPoint(x: x0, y: h))
                fillPath.closeSubpath()

                context.fill(fillPath, with: .color(points[i].color.opacity(0.15)))
            }
        }
    }

    private func segmentLines(w: CGFloat, h: CGFloat) -> some View {
        Canvas { context, _ in
            let stepX = w / CGFloat(max(points.count - 1, 1))

            for i in 0..<(points.count - 1) {
                let x0 = stepX * CGFloat(i)
                let x1 = stepX * CGFloat(i + 1)
                let y0 = h * CGFloat(1.0 - min(max(0, points[i].value), maxY) / maxY)
                let y1 = h * CGFloat(1.0 - min(max(0, points[i + 1].value), maxY) / maxY)

                var linePath = Path()
                linePath.move(to: CGPoint(x: x0, y: y0))
                linePath.addLine(to: CGPoint(x: x1, y: y1))

                context.stroke(linePath, with: .color(points[i].color), lineWidth: small ? 1.0 : 1.5)
            }
        }
    }
}

// MARK: - Adaptive Grid

struct AdaptiveGrid<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        let items = [GridItem](repeating: GridItem(.flexible(), spacing: 6), count: 3)
        LazyVGrid(columns: items, spacing: 6) {
            content()
        }
    }
}
