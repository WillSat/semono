import Foundation

/// Per-window cache of `system_profiler` reports. Each data type is fetched
/// lazily and remembered for the lifetime of the Device Information window;
/// Refresh replaces the entry without emptying the view first.
@MainActor
final class DeviceInfoStore: ObservableObject {
    @Published private(set) var reports: [DeviceCategory: DeviceReport] = [:]
    @Published private(set) var failures: [DeviceCategory: String] = [:]
    @Published private(set) var loading: Set<DeviceCategory> = []

    private var tasks: [DeviceCategory: Task<Void, Never>] = [:]
    /// Identifies the current load for a category so a cancelled request that
    /// finishes late cannot clear the loading state of its replacement.
    private var tokens: [DeviceCategory: UUID] = [:]

    func report(for category: DeviceCategory) -> DeviceReport? {
        reports[category]
    }

    func failure(for category: DeviceCategory) -> String? {
        failures[category]
    }

    func isLoading(_ category: DeviceCategory) -> Bool {
        loading.contains(category)
    }

    func load(_ category: DeviceCategory, force: Bool = false) {
        if isLoading(category) {
            guard force else { return }
            tasks[category]?.cancel()
        } else if !force, reports[category] != nil {
            return
        }

        let token = UUID()
        tokens[category] = token
        failures[category] = nil
        loading.insert(category)

        let task = Task { [weak self] in
            do {
                let report = try await SystemProfilerClient.report(for: category)
                guard let self, self.tokens[category] == token else { return }
                self.reports[category] = report
                self.failures[category] = nil
            } catch is CancellationError {
                // A cancelled load keeps whatever was already cached.
            } catch {
                guard let self, self.tokens[category] == token else { return }
                self.failures[category] = error.localizedDescription
            }

            guard let self, self.tokens[category] == token else { return }
            self.loading.remove(category)
            self.tasks[category] = nil
            self.tokens[category] = nil
        }
        tasks[category] = task
    }
}
