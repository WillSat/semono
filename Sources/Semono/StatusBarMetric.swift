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
        case .cpu: "\(Int(metrics.cpuUsage * 100))%"
        case .gpu: "\(Int(metrics.gpuUsage * 100))%"
        case .pwr: MetricFormat.power(metrics.powerUsage)
        case .memory: "\(Int(metrics.memoryUsage * 100))%"
        }
    }
}
