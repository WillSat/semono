import Foundation

/// What the status bar item reads out.
///
/// The raw values are persisted UserDefaults strings; the first four keep
/// their historical values so existing preferences survive the update. The
/// icon case means "no live data": only the Semono mark is drawn.
enum StatusBarMetric: String, CaseIterable, Identifiable {
    case cpu = "cpu"
    case gpu = "gpu"
    case pwr = "pwr"
    case memory = "memory"
    case pressure = "pressure"
    case network = "network"
    case icon = "icon"

    var id: String { rawValue }

    /// Tiny label drawn above the value in the menu bar. Empty in icon mode.
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .pwr: "PWR"
        case .memory: "MEM"
        case .pressure: "PRS"
        case .network: "NET"
        case .icon: ""
        }
    }

    /// Localization key used by the settings window.
    var settingsTitleKey: String {
        switch self {
        case .cpu: "CPU Usage"
        case .gpu: "GPU Usage"
        case .pwr: "Power Draw"
        case .memory: "Memory Usage"
        case .pressure: "Memory Pressure"
        case .network: "Network"
        case .icon: "Icon Only"
        }
    }

    /// Localization key for the one-line explanation in settings.
    var settingsDescriptionKey: String {
        switch self {
        case .cpu: "Show CPU usage percentage."
        case .gpu: "Show GPU usage percentage."
        case .pwr: "Show power draw in watts."
        case .memory: "Show memory usage percentage."
        case .pressure: "Show the memory pressure level (#N, #W, #C)."
        case .network: "Show connection type, Wi-Fi signal and upload/download speed."
        case .icon: "Show only the Semono mark, without live data."
        }
    }

    var settingsIcon: String {
        switch self {
        case .cpu: "cpu"
        case .gpu: "display"
        case .pwr: "bolt.fill"
        case .memory: "memorychip"
        case .pressure: "gauge.with.dots.needle.67percent"
        case .network: "network"
        case .icon: "chart.xyaxis.line"
        }
    }

    var isIconOnly: Bool { self == .icon }

    /// Current readout for this metric. The result is a value type so the
    /// status bar view can skip redrawing when nothing changed.
    @MainActor
    func readout(from metrics: MetricsCollector) -> StatusBarReadout {
        switch self {
        case .cpu:
            return percentReadout(label: label, value: metrics.cpuUsage)
        case .gpu:
            return percentReadout(label: label, value: metrics.gpuUsage)
        case .pwr:
            let value = metrics.powerUsage.map(MetricFormat.power) ?? "—"
            return StatusBarReadout(top: label, bottom: value, accessibility: "Power, \(value) watts")
        case .memory:
            return percentReadout(label: label, value: metrics.memoryUsage)
        case .pressure:
            let level = metrics.memoryPressureLevel
            let tag = level.map { "#\(MemoryPressure.abbreviation(for: $0))" } ?? "—"
            return StatusBarReadout(
                top: label,
                bottom: tag,
                pressureLevel: level,
                accessibility: "Memory pressure, \(tag)"
            )
        case .network:
            var top = metrics.networkType ?? "—"
            if top == "WiFi", let rssi = metrics.wifiRSSI {
                top += " \(rssi)"
            }
            let down = Self.compactSpeed(metrics.downloadSpeed)
            let up = Self.compactSpeed(metrics.uploadSpeed)
            return StatusBarReadout(
                top: top,
                bottom: "\u{2193}\(down) \u{2191}\(up)",
                accessibility: "\(top), down \(down), up \(up)"
            )
        case .icon:
            return .iconOnly
        }
    }

    @MainActor
    private func percentReadout(label: String, value: Double?) -> StatusBarReadout {
        let text = value.map { "\(Int($0 * 100))%" } ?? "—"
        return StatusBarReadout(top: label, bottom: text, accessibility: "\(label), \(text)")
    }

    private static func compactSpeed(_ value: Double?) -> String {
        guard let value else { return "—" }
        return MetricFormat.speed(value).trimmingCharacters(in: .whitespaces)
    }
}

/// One frame of menu bar content: the tiny type label above, the value below,
/// or the Semono mark when the metric is icon-only.
struct StatusBarReadout: Equatable {
    var top: String = ""
    var bottom: String = ""
    var pressureLevel: Int?
    var accessibility: String = ""
    var isIcon: Bool = false

    static let iconOnly = StatusBarReadout(accessibility: "Semono", isIcon: true)

    init(
        top: String = "",
        bottom: String = "",
        pressureLevel: Int? = nil,
        accessibility: String = "",
        isIcon: Bool = false
    ) {
        self.top = top
        self.bottom = bottom
        self.pressureLevel = pressureLevel
        self.accessibility = accessibility
        self.isIcon = isIcon
    }
}
