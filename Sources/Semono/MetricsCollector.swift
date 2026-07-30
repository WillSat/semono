import Foundation
import Darwin
import SystemConfiguration
import CoreWLAN

@MainActor
final class MetricsCollector: ObservableObject {
    @Published var gpuUsage: Double = 0
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    @Published var powerUsage: Double = 0
    @Published var downloadSpeed: Double = 0
    @Published var uploadSpeed: Double = 0
    @Published var networkType: String = ""
    @Published var wifiRSSI: Int = 0
    @Published var memoryPressureLevel: Int = 0
    @Published var swapBytes: UInt64 = 0
    @Published var swapRatio: Double = 0
    @Published var diskReadSpeed: Double = 0
    @Published var diskWriteSpeed: Double = 0
    @Published var thermalState: Int = 0

    private var prevCpuUsed: UInt64 = 0
    private var prevCpuTotal: UInt64 = 0
    private var prevNetRx: UInt64 = 0
    private var prevNetTx: UInt64 = 0
    private var prevNetTime: Date = .now
    private var hasPrevNet: Bool = false
    private var prevDiskReadBytes: UInt64 = 0
    private var prevDiskWriteBytes: UInt64 = 0
    private var prevDiskTime: Date = .now
    private var hasPrevDisk: Bool = false
    private var updateTask: Task<Void, Never>?
    private var sampleCount: Int = 0
    private var cachedPower: Double = 0

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
        let s = SettingsStore.shared
        let sb = s.statusBarMetric
        let collectGPU = s.showComputeColumn || sb == "gpu"
        let collectCPU = s.showComputeColumn || sb == "cpu"
        let collectMemory = s.showMemoryColumn || sb == "memory"
        let collectPower = s.showComputeColumn || sb == "pwr"
        let collectStorage = s.showStorageColumn
        let collectNetwork = s.showNetworkColumn

        if collectGPU { gpuUsage = Self.readGPU() }
        if collectCPU { cpuUsage = readCPU() }

        if collectMemory {
            memoryUsage = readMemory()
            (memoryPressureLevel, swapBytes, swapRatio) = readSwapAndPressure()
        }

        if collectStorage { thermalState = readThermalState() }

        if collectPower {
            if sampleCount % 2 == 0 { cachedPower = Self.readPower() }
            powerUsage = cachedPower
        }

        if collectNetwork {
            let (down, up) = readNetwork()
            downloadSpeed = down
            uploadSpeed = up
            let (connType, rssi) = Self.readConnectionInfo()
            networkType = connType
            wifiRSSI = rssi
        }

        if collectStorage {
            let (diskR, diskW) = readDisk()
            diskReadSpeed = diskR
            diskWriteSpeed = diskW
        }

        sampleCount &+= 1
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
        guard result == KERN_SUCCESS, cpuInfo != nil else { return 0 }

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

    private static let pageSize = Double(sysconf(Int32(_SC_PAGESIZE)))
    private static let totalMemory: Double = {
        var info = host_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                _ = host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        return Double(info.max_mem)
    }()

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

        let active     = Double(info.active_count) * Self.pageSize
        let wired      = Double(info.wire_count) * Self.pageSize
        let compressed = Double(info.compressor_page_count) * Self.pageSize
        let used = active + wired + compressed

        guard Self.totalMemory > 0 else { return 0 }
        return min(1.0, used / Self.totalMemory)
    }

    // MARK: - Memory Pressure + Swap

    private func readSwapAndPressure() -> (pressure: Int, swapBytes: UInt64, swapRatio: Double) {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)

        var swapSize = 0
        sysctlbyname("vm.swapusage", nil, &swapSize, nil, 0)
        guard swapSize > 0 else { return (Int(level), 0, 0) }

        var buf = [CChar](repeating: 0, count: swapSize)
        sysctlbyname("vm.swapusage", &buf, &swapSize, nil, 0)
        let str = String(cString: buf)

        let usedBytes = parseSwapField(str, key: "used")
        let totalBytes = parseSwapField(str, key: "total")
        let ratio: Double = totalBytes > 0 ? min(1.0, Double(usedBytes) / Double(totalBytes)) : 0

        return (Int(level), UInt64(usedBytes), ratio)
    }

    private func parseSwapField(_ str: String, key: String) -> Double {
        guard let range = str.range(of: "\(key) = ") else { return 0 }
        let after = str[range.upperBound...]
        let parts = after.split(separator: " ")
        guard let token = parts.first else { return 0 }
        let raw = String(token)
        guard let numEnd = raw.firstIndex(where: { !$0.isNumber && $0 != "." }) else { return 0 }
        let value = Double(raw[..<numEnd]) ?? 0
        let unit = String(raw[numEnd...]).uppercased()
        switch unit {
        case "G": return value * 1_000_000_000
        case "M": return value * 1_000_000
        case "K": return value * 1_000
        default:  return value
        }
    }

    // MARK: - Thermal

    private func readThermalState() -> Int {
        Int(ProcessInfo.processInfo.thermalState.rawValue)
    }

    // MARK: - GPU

    nonisolated private static func readGPU() -> Double {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/gpu_helper")
        let task = Process()
        task.executableURL = helperURL
        let pipe = Pipe()
        task.standardOutput = pipe
        guard let _ = try? task.run() else { return 0 }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return min(1.0, (Double(raw) ?? 0) / 100.0)
    }

    // MARK: - Power

    nonisolated private static func readPower() -> Double {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/power_helper")
        let task = Process()
        task.executableURL = helperURL
        let pipe = Pipe()
        task.standardOutput = pipe
        guard let _ = try? task.run() else { return 0 }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
        return (Double(raw) ?? 0) / 1000.0
    }

    // MARK: - Disk

    private func readDisk() -> (Double, Double) {
        guard let (r, w) = Self.readDiskBytes() else {
            return (0, 0)
        }
        let now = Date()

        guard hasPrevDisk else {
            prevDiskReadBytes = r; prevDiskWriteBytes = w; prevDiskTime = now
            hasPrevDisk = true
            return (0, 0)
        }

        let dt = now.timeIntervalSince(prevDiskTime)
        guard dt > 0 else {
            prevDiskReadBytes = r; prevDiskWriteBytes = w; prevDiskTime = now
            return (0, 0)
        }

        let rDelta = r >= prevDiskReadBytes ? r - prevDiskReadBytes : 0
        let wDelta = w >= prevDiskWriteBytes ? w - prevDiskWriteBytes : 0
        let readSpeed  = Double(rDelta) / dt
        let writeSpeed = Double(wDelta) / dt
        prevDiskReadBytes = r; prevDiskWriteBytes = w; prevDiskTime = now
        return (readSpeed, writeSpeed)
    }

    nonisolated private static func readDiskBytes() -> (UInt64, UInt64)? {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/disk_helper")
        let task = Process()
        task.executableURL = helperURL
        let pipe = Pipe()
        task.standardOutput = pipe
        guard let _ = try? task.run() else { return nil }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let parts = raw.split(separator: " ")
        guard parts.count == 2,
              let r = UInt64(parts[0]),
              let w = UInt64(parts[1]) else { return nil }
        return (r, w)
    }

    // MARK: - Network Bytes

    private func readNetwork() -> (Double, Double) {
        guard let (tx, rx) = Self.readNetworkBytes() else {
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

    // MARK: - Connection type + RSSI

    nonisolated private static func readConnectionInfo() -> (type: String, rssi: Int) {
        guard let store = SCDynamicStoreCreate(nil, "Semono" as CFString, nil, nil) else {
            return ("---", 0)
        }
        guard let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primaryID = global["PrimaryService"] as? String,
              let svc = SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\(primaryID)/Interface" as CFString) as? [String: Any],
              let hardware = svc["Hardware"] as? String
        else {
            return ("---", 0)
        }

        if hardware == "AirPort" {
            let rssi = CWWiFiClient.shared().interface()?.rssiValue() ?? 0
            return ("WiFi", rssi)
        }
        return ("Eth", 0)
    }

    // MARK: - Shared helpers

    nonisolated private static func readNetworkBytes() -> (tx: UInt64, rx: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(first) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            guard let ifa = ptr else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            guard name == "en0" else { continue }
            guard let sa = ifa.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_LINK) else { continue }
            let data = ifa.pointee.ifa_data.assumingMemoryBound(to: if_data.self).pointee
            return (tx: UInt64(data.ifi_obytes), rx: UInt64(data.ifi_ibytes))
        }
        return nil
    }

    private static let kCPUStateMax    = Int32(4)
    private static let kCPUStateUser   = Int32(0)
    private static let kCPUStateSystem = Int32(1)
    private static let kCPUStateIdle   = Int32(2)
    private static let kCPUStateNice   = Int32(3)
}

private typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
