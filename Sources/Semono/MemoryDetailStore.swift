import AppKit
import Darwin
import Foundation

struct MemoryProcess: Sendable {
    let pid: Int32
    let command: String
    let bytes: UInt64
}

struct MemoryCategory: Identifiable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case app
        case wired
        case compressed
        case cached
        case free

        var titleKey: String {
            switch self {
            case .app: "App Memory"
            case .wired: "Wired"
            case .compressed: "Compressed"
            case .cached: "Cached Files"
            case .free: "Free"
            }
        }
    }

    let kind: Kind
    let bytes: UInt64
    var id: String { kind.rawValue }
}

struct MemoryDetailSnapshot: Sendable {
    let totalBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let cachedBytes: UInt64
    let freeBytes: UInt64
    let swapUsedBytes: UInt64?
    let swapTotalBytes: UInt64?
    let pressureLevel: Int?
    let processes: [MemoryProcess]
    let timestamp: Date

    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(usedBytes) / Double(totalBytes))
    }

    var swapFraction: Double {
        guard let used = swapUsedBytes, let total = swapTotalBytes, total > 0 else { return 0 }
        return min(1, Double(used) / Double(total))
    }

    var categories: [MemoryCategory] {
        [
            MemoryCategory(kind: .app, bytes: appBytes),
            MemoryCategory(kind: .wired, bytes: wiredBytes),
            MemoryCategory(kind: .compressed, bytes: compressedBytes),
            MemoryCategory(kind: .cached, bytes: cachedBytes),
            MemoryCategory(kind: .free, bytes: freeBytes),
        ]
    }
}

struct MemoryAppUsage: Identifiable {
    let id: Int32
    let name: String
    let icon: NSImage?
    let bytes: UInt64
    let percentOfTotal: Double
}

enum MemoryDetailSampler {
    static func sample() -> MemoryDetailSnapshot? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        let page = UInt64(sysconf(Int32(_SC_PAGESIZE)))

        let appPages = max(0, Int64(info.internal_page_count) - Int64(info.purgeable_count))
        let app = UInt64(appPages) * page
        let wired = UInt64(info.wire_count) * page
        let compressed = UInt64(info.compressor_page_count) * page
        let cached = (UInt64(info.external_page_count) + UInt64(info.purgeable_count)) * page

        let used = app + wired + compressed
        let free = total > used + cached ? total - used - cached : 0

        let swap = readSwap()
        let pressure = readPressure()
        let processes = readProcesses()

        return MemoryDetailSnapshot(
            totalBytes: total,
            appBytes: app,
            wiredBytes: wired,
            compressedBytes: compressed,
            cachedBytes: cached,
            freeBytes: free,
            swapUsedBytes: swap?.used,
            swapTotalBytes: swap?.total,
            pressureLevel: pressure,
            processes: processes,
            timestamp: Date()
        )
    }

    private static func readSwap() -> (total: UInt64, used: UInt64)? {
        var size = 0
        guard sysctlbyname("vm.swapusage", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [CChar](repeating: 0, count: size)
        var outSize = size
        guard sysctlbyname("vm.swapusage", &buffer, &outSize, nil, 0) == 0, outSize > 0 else {
            return nil
        }
        let parsed = SwapParser.usage(from: buffer, size: outSize)
        guard parsed.total > 0 else { return nil }
        return parsed
    }

    private static func readPressure() -> Int? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return nil
        }
        return MemoryPressure.level(fromRaw: Int(level))
    }

    private static func readProcesses() -> [MemoryProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,rss=,comm="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return parseProcesses(data)
        } catch {
            return []
        }
    }

    private static func parseProcesses(_ data: Data) -> [MemoryProcess] {
        guard let output = String(data: data, encoding: .utf8) else { return [] }
        var processes: [MemoryProcess] = []
        processes.reserveCapacity(128)

        for line in output.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3,
                  let pid = Int32(parts[0]),
                  let rssKB = UInt64(parts[1])
            else { continue }
            let command = String(parts[2]).trimmingCharacters(in: .whitespaces)
            let bytes = rssKB &* 1024
            guard bytes > 0 else { continue }
            processes.append(MemoryProcess(pid: pid, command: command, bytes: bytes))
        }

        // Activity Monitor's "Memory" column is the physical footprint, not
        // RSS. Prefer it when libproc can read the process; fall back to RSS
        // for processes we cannot inspect.
        let candidates = Array(processes.sorted { $0.bytes > $1.bytes }.prefix(80))
        let enriched = candidates.map { process in
            MemoryProcess(
                pid: process.pid,
                command: process.command,
                bytes: physicalFootprint(pid: process.pid) ?? process.bytes
            )
        }
        return Array(enriched.sorted { $0.bytes > $1.bytes }.prefix(40))
    }

    private static func physicalFootprint(pid: Int32) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            let raw = UnsafeMutableRawPointer(infoPtr)
                .assumingMemoryBound(to: rusage_info_t?.self)
            return proc_pid_rusage(pid, RUSAGE_INFO_V4, raw)
        }
        guard result == 0, info.ri_phys_footprint > 0 else { return nil }
        return info.ri_phys_footprint
    }
}

@MainActor
final class MemoryDetailStore: ObservableObject {
    @Published private(set) var snapshot: MemoryDetailSnapshot?
    @Published private(set) var apps: [MemoryAppUsage] = []
    @Published private(set) var isRefreshing = false

    private var timer: Timer?
    private var interval: TimeInterval = 3
    private var isRunning = false

    func start(interval: TimeInterval) {
        self.interval = max(1, interval)
        isRunning = true
        refresh()
        scheduleTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func updateInterval(_ interval: TimeInterval) {
        self.interval = max(1, interval)
        guard isRunning else { return }
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer.tolerance = min(0.5, interval * 0.1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        guard isRunning, !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor in
            let snapshot = await Task.detached(priority: .utility) {
                MemoryDetailSampler.sample()
            }.value
            guard isRunning else {
                isRefreshing = false
                return
            }
            if let snapshot {
                apply(snapshot)
            }
            isRefreshing = false
        }
    }

    private func apply(_ snapshot: MemoryDetailSnapshot) {
        self.snapshot = snapshot
        let mapped = snapshot.processes.compactMap { process -> MemoryAppUsage? in
            guard let app = NSRunningApplication(processIdentifier: process.pid),
                  app.activationPolicy == .regular
            else { return nil }
            let name = app.localizedName
                ?? URL(fileURLWithPath: process.command).lastPathComponent
            return MemoryAppUsage(
                id: process.pid,
                name: name,
                icon: app.icon,
                bytes: process.bytes,
                percentOfTotal: snapshot.totalBytes > 0
                    ? Double(process.bytes) / Double(snapshot.totalBytes)
                    : 0
            )
        }
        apps = Array(mapped.sorted { $0.bytes > $1.bytes }.prefix(10))
    }
}
