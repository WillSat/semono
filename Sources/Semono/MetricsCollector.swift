import Foundation
import Darwin

@MainActor
final class MetricsCollector: ObservableObject {
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0

    private var prevCpuUsed: UInt64 = 0
    private var prevCpuTotal: UInt64 = 0
    private var prevNetRx: UInt64 = 0
    private var prevNetTx: UInt64 = 0
    private var prevNetTime: Date = .now
    private var hasPrevNet: Bool = false
    private var updateTask: Task<Void, Never>?

    func start() {
        updateTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.sample()
                let interval = Double(SettingsStore.shared.refreshInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    private func sample() {
        cpuUsage = readCPU()
        memoryUsage = readMemory()
        let (down, up) = readNetwork()
        downloadSpeed = down
        uploadSpeed = up
    }

    // MARK: - CPU

    private func readCPU() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS else { return 0 }

        let cpuCount = Int(numCPUs)
        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0

        for i in 0..<cpuCount {
            let base = Int(Self.kCPUStateMax) * i
            user   += UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateUser))])
            system += UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateSystem))])
            idle   += UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateIdle))])
            nice   += UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateNice))])
        }

        let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(numCpuInfo))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        let used = UInt64(user) + UInt64(system) + UInt64(nice)
        let total = used + UInt64(idle)

        guard prevCpuTotal > 0, total > prevCpuTotal else {
            prevCpuUsed = used
            prevCpuTotal = total
            return 0
        }

        let usedDelta = used - prevCpuUsed
        let totalDelta = total - prevCpuTotal
        prevCpuUsed = used
        prevCpuTotal = total

        guard totalDelta > 0 else { return 0 }
        return min(1.0, Double(usedDelta) / Double(totalDelta))
    }

    // MARK: - Memory

    private func readMemory() -> Double {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(sysconf(Int32(_SC_PAGESIZE)))
        let active     = Double(info.active_count) * pageSize
        let wired      = Double(info.wire_count) * pageSize
        let compressed = Double(info.compressor_page_count) * pageSize
        let used = active + wired + compressed

        var hostInfo = host_basic_info()
        var hostCount = mach_msg_type_number_t(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let hostResult = withUnsafeMutablePointer(to: &hostInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(hostCount)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &hostCount)
            }
        }
        guard hostResult == KERN_SUCCESS else { return 0 }
        let total = Double(hostInfo.max_mem)

        guard total > 0 else { return 0 }
        return min(1.0, used / total)
    }

    // MARK: - Network

    private func readNetwork() -> (Double, Double) {
        guard let (tx, rx) = Self.readNetworkBytes(interface: "en0") else {
            return (0, 0)
        }
        let now = Date()

        guard hasPrevNet else {
            prevNetRx = rx; prevNetTx = tx; prevNetTime = now
            hasPrevNet = true
            return (0, 0)
        }

        let dt = now.timeIntervalSince(prevNetTime)
        guard dt > 0 else {
            prevNetRx = rx; prevNetTx = tx; prevNetTime = now
            return (0, 0)
        }

        let rxDelta = rx >= prevNetRx ? rx - prevNetRx : 0
        let txDelta = tx >= prevNetTx ? tx - prevNetTx : 0
        let down = Double(rxDelta) / dt
        let up   = Double(txDelta) / dt
        prevNetRx = rx; prevNetTx = tx; prevNetTime = now
        return (down, up)
    }

    private static let kCPUStateMax    = Int32(4)
    private static let kCPUStateUser   = Int32(0)
    private static let kCPUStateSystem = Int32(1)
    private static let kCPUStateIdle   = Int32(2)
    private static let kCPUStateNice   = Int32(3)

    nonisolated private static func readNetworkBytes(interface: String) -> (tx: UInt64, rx: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let ifa = ptr else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name == interface else { continue }
            guard let sa = ifa.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let data = ifa.pointee.ifa_data.assumingMemoryBound(to: if_data.self).pointee
            return (tx: UInt64(data.ifi_obytes), rx: UInt64(data.ifi_ibytes))
        }
        return nil
    }
}

private typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
