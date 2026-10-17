import Foundation

/// Which metric the menu bar readout shows. Raw values are the persisted
/// UserDefaults strings, so existing preferences keep working across updates.
enum StatusBarMetric: String, CaseIterable, Identifiable {
    case cpu = "cpu"
    case gpu = "gpu"
    case pwr = "pwr"
    case memory = "memory"

    var id: String { rawValue }

    /// Short label rendered next to the value in the menu bar / picker.
    var label: String {
        switch self {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .pwr: "PWR"
        case .memory: "MEM"
        }
    }

    /// Current readout text for this metric, e.g. "42%" or "12.3".
    @MainActor
    func text(from metrics: MetricsCollector) -> String {
        switch self {
        case .cpu: metrics.cpuUsage.map { "\(Int($0 * 100))%" } ?? "—"
        case .gpu: metrics.gpuUsage.map { "\(Int($0 * 100))%" } ?? "—"
        case .pwr: metrics.powerUsage.map(MetricFormat.power) ?? "—"
        case .memory: metrics.memoryUsage.map { "\(Int($0 * 100))%" } ?? "—"
        }
    }
}
