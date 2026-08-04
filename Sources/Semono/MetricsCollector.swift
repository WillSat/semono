import Foundation
import Darwin
import SystemConfiguration
import CoreWLAN
import IOKit
import os

@MainActor
final class MetricsCollector: ObservableObject {
    @Published var gpuUsage: Double = 0
    @Published var cpuUsage: Double = 0
    @Published var perCoreCPU: [Double] = []
    @Published var perCoreFreqMHz: [Double] = []
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

    init() {}

    private var updateTask: Task<Void, Never>?

    func start() {
        updateTask = Task { [weak self] in
            var sampler = Sampler()
            while !Task.isCancelled {
                guard let self else { return }
                let s = SettingsStore.shared
                let sb = s.statusBarMetric
                let flags = Sampler.Flags(
                    collectGPU: s.showComputeColumn || sb == "gpu",
                    collectCPU: s.showComputeColumn || sb == "cpu",
                    collectMemory: s.showMemoryColumn || sb == "memory",
                    collectPower: s.showComputeColumn || sb == "pwr",
                    collectStorage: s.showStorageColumn,
                    collectNetwork: s.showNetworkColumn
                )
                let sample = await sampler.sampleOnce(flags: flags)
                self.apply(sample)

                let interval = Double(SettingsStore.shared.refreshInterval)
                // Tolerance lets the kernel coalesce this wakeup with other
                // system timers instead of the process waking alone on every
                // tick; the HUD needs no tick-level precision.
                try? await Task.sleep(
                    for: .seconds(interval),
                    tolerance: .seconds(min(interval * 0.2, 1.0))
                )
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
        StatsHelper.shared.shutdown()
    }

    /// Publishes a sample. @Published fires only on actual value changes so
    /// the HUD does not re-render when the metrics are static.
    private func apply(_ s: Sampler.Sample) {
        if gpuUsage != s.gpuUsage { gpuUsage = s.gpuUsage }
        if cpuUsage != s.cpuUsage { cpuUsage = s.cpuUsage }
        if perCoreCPU != s.perCoreCPU { perCoreCPU = s.perCoreCPU }
        if perCoreFreqMHz != s.perCoreFreqMHz { perCoreFreqMHz = s.perCoreFreqMHz }
        if memoryUsage != s.memoryUsage { memoryUsage = s.memoryUsage }
        if powerUsage != s.powerUsage { powerUsage = s.powerUsage }
        if downloadSpeed != s.downloadSpeed { downloadSpeed = s.downloadSpeed }
        if uploadSpeed != s.uploadSpeed { uploadSpeed = s.uploadSpeed }
        if networkType != s.networkType { networkType = s.networkType }
        if wifiRSSI != s.wifiRSSI { wifiRSSI = s.wifiRSSI }
        if memoryPressureLevel != s.memoryPressureLevel { memoryPressureLevel = s.memoryPressureLevel }
        if swapBytes != s.swapBytes { swapBytes = s.swapBytes }
        if swapRatio != s.swapRatio { swapRatio = s.swapRatio }
        if diskReadSpeed != s.diskReadSpeed { diskReadSpeed = s.diskReadSpeed }
        if diskWriteSpeed != s.diskWriteSpeed { diskWriteSpeed = s.diskWriteSpeed }
        if thermalState != s.thermalState { thermalState = s.thermalState }

        // History is only maintained while the monitor window is on screen;
        // otherwise each tick's snapshot allocation is pure overhead.
        if MetricsHistory.shared.isRecording {
            MetricsHistory.shared.record(from: self)
        }
    }
}

// MARK: - Sampler

/// Collects one metrics snapshot off the main actor. All heavy work (IOKit
/// walks, CoreWLAN, helper subprocesses, mach/sysctl calls) runs on the
/// cooperative pool; the main actor only receives the finished `Sample`.
struct Sampler: Sendable {
    struct Flags: Sendable {
        var collectGPU: Bool
        var collectCPU: Bool
        var collectMemory: Bool
        var collectPower: Bool
        var collectStorage: Bool
        var collectNetwork: Bool
    }

    struct Sample: Sendable {
        var gpuUsage: Double = 0
        var cpuUsage: Double = 0
        var perCoreCPU: [Double] = []
        var perCoreFreqMHz: [Double] = []
        var memoryUsage: Double = 0
        var powerUsage: Double = 0
        var downloadSpeed: Double = 0
        var uploadSpeed: Double = 0
        var networkType: String = ""
        var wifiRSSI: Int = 0
        var memoryPressureLevel: Int = 0
        var swapBytes: UInt64 = 0
        var swapRatio: Double = 0
        var diskReadSpeed: Double = 0
        var diskWriteSpeed: Double = 0
        var thermalState: Int = 0
    }

    // Slow-moving readings are cached and refreshed on longer intervals.
    private static let freqCacheInterval: TimeInterval = 30
    private static let connCacheInterval: TimeInterval = 15
    private static let swapCacheInterval: TimeInterval = 10

    private var prevCpuUsed: UInt64 = 0
    private var prevCpuTotal: UInt64 = 0
    private var prevPerCoreUsed: [UInt64] = []
    private var prevPerCoreTotal: [UInt64] = []
    private var prevNetRx: UInt64 = 0
    private var prevNetTx: UInt64 = 0
    private var prevNetTime: Date = .now
    private var hasPrevNet: Bool = false
    private var prevDiskReadBytes: UInt64 = 0
    private var prevDiskWriteBytes: UInt64 = 0
    private var prevDiskTime: Date = .now
    private var hasPrevDisk: Bool = false
    private var sampleCount: Int = 0
    private var cachedPower: Double = 0
    private var freqCacheDate = Date.distantPast
    private var cachedFreq: [Double] = []
    private var connCacheDate = Date.distantPast
    private var cachedConnType = ""
    private var cachedRSSI = 0
    private var cachedInterfaceName = "en0"
    private var swapCacheDate = Date.distantPast
    private var cachedSwap: (Int, UInt64, Double) = (0, 0, 0)

    mutating func sampleOnce(flags: Flags) async -> Sample {
        var s = Sample()
        let now = Date()

        let wantsGPU = flags.collectGPU
        let wantsPower = flags.collectPower
        let wantsDisk = flags.collectStorage
        // When two or more helper-backed metrics are live, a single "all"
        // request serves them in one pipe round-trip and one IOKit pass.
        // A lone metric keeps its dedicated query (and the previous
        // every-second-tick staggering for power/disk).
        if (wantsGPU ? 1 : 0) + (wantsPower ? 1 : 0) + (wantsDisk ? 1 : 0) >= 2 {
            let (gpu, power, disk) = await Self.readAll()
            if wantsGPU { s.gpuUsage = gpu }
            if wantsPower { s.powerUsage = power }
            if wantsDisk {
                (s.diskReadSpeed, s.diskWriteSpeed) = readDisk(disk)
            }
        } else {
            if wantsGPU {
                s.gpuUsage = await Self.readGPU()
            }
            if wantsPower {
                if sampleCount % 2 == 0 { cachedPower = await Self.readPower() }
                s.powerUsage = cachedPower
            }
            if wantsDisk && sampleCount % 2 == 1 {
                (s.diskReadSpeed, s.diskWriteSpeed) = readDisk(await Self.readDiskBytes())
            }
        }
        if flags.collectCPU {
            (s.cpuUsage, s.perCoreCPU) = readCPU()
            if now.timeIntervalSince(freqCacheDate) >= Self.freqCacheInterval {
                cachedFreq = Self.readPerCoreFrequencies()
                freqCacheDate = now
            }
            s.perCoreFreqMHz = cachedFreq
        }

        if flags.collectMemory {
            s.memoryUsage = Self.readMemory()
            if now.timeIntervalSince(swapCacheDate) >= Self.swapCacheInterval {
                cachedSwap = Self.readSwapAndPressure()
                swapCacheDate = now
            }
            (s.memoryPressureLevel, s.swapBytes, s.swapRatio) = cachedSwap
        }

        s.thermalState = Self.readThermalState()

        if flags.collectNetwork {
            (s.downloadSpeed, s.uploadSpeed) = readNetwork()
            if now.timeIntervalSince(connCacheDate) >= Self.connCacheInterval {
                (cachedConnType, cachedRSSI, cachedInterfaceName) = Self.readConnectionInfo()
                connCacheDate = now
            }
            s.networkType = cachedConnType
            s.wifiRSSI = cachedRSSI
        }

        sampleCount &+= 1
        return s
    }

    // MARK: - CPU

    private mutating func readCPU() -> (Double, [Double]) {
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
        guard result == KERN_SUCCESS, cpuInfo != nil else { return (0, []) }

        let cpuCount = Int(numCPUs)
        var user: UInt32 = 0
        var system: UInt32 = 0
        var idle: UInt32 = 0
        var nice: UInt32 = 0

        var perCoreNowUsed: [UInt64] = []
        var perCoreNowTotal: [UInt64] = []

        for i in 0..<cpuCount {
            let base = Int(Self.kCPUStateMax) * i
            let u = UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateUser))])
            let s = UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateSystem))])
            let id = UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateIdle))])
            let n = UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateNice))])

            user   += u
            system += s
            idle   += id
            nice   += n

            let coreUsed = UInt64(u) + UInt64(s) + UInt64(n)
            let coreTotal = coreUsed + UInt64(id)
            perCoreNowUsed.append(coreUsed)
            perCoreNowTotal.append(coreTotal)
        }

        let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(numCpuInfo))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), size)

        let used = UInt64(user) + UInt64(system) + UInt64(nice)
        let total = used + UInt64(idle)

        var aggregate: Double = 0
        if prevCpuTotal > 0, total > prevCpuTotal {
            let usedDelta = used >= prevCpuUsed ? used - prevCpuUsed : 0
            let totalDelta = total - prevCpuTotal
            aggregate = min(1.0, Double(usedDelta) / Double(totalDelta))
        }
        prevCpuUsed = used
        prevCpuTotal = total

        var perCore: [Double] = Array(repeating: 0, count: cpuCount)
        if prevPerCoreUsed.count == cpuCount {
            for i in 0..<cpuCount {
                guard perCoreNowTotal[i] > prevPerCoreTotal[i] else { continue }
                let uDelta = perCoreNowUsed[i] >= prevPerCoreUsed[i]
                    ? perCoreNowUsed[i] - prevPerCoreUsed[i]
                    : 0
                let tDelta = perCoreNowTotal[i] - prevPerCoreTotal[i]
                if tDelta > 0 {
                    perCore[i] = min(1.0, Double(uDelta) / Double(tDelta))
                }
            }
        }
        prevPerCoreUsed = perCoreNowUsed
        prevPerCoreTotal = perCoreNowTotal

        return (aggregate, perCore)
    }

    // MARK: - Memory

    private static let pageSize = Double(sysconf(Int32(_SC_PAGESIZE)))
    private static let totalMemory: Double = Double(readPhysicalMemory())

    private static func readMemory() -> Double {
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

        // Approximates Activity Monitor's "App + Wired + Compressed": app
        // pages are the internal (non-file-backed) pages minus the purgeable
        // ones, instead of the whole active set which over-counts reclaimable
        // file cache pages.
        let app        = (Double(info.internal_page_count) - Double(info.purgeable_count)) * Self.pageSize
        let wired      = Double(info.wire_count) * Self.pageSize
        let compressed = Double(info.compressor_page_count) * Self.pageSize
        let used = max(0, app) + wired + compressed

        guard Self.totalMemory > 0 else { return 0 }
        return min(1.0, used / Self.totalMemory)
    }

    // MARK: - Memory Pressure + Swap

    private static func readSwapAndPressure() -> (pressure: Int, swapBytes: UInt64, swapRatio: Double) {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)

        var swapSize = 0
        sysctlbyname("vm.swapusage", nil, &swapSize, nil, 0)
        guard swapSize > 0 else { return (Int(level), 0, 0) }

        var buf = [CChar](repeating: 0, count: swapSize)
        var outSize = swapSize
        guard sysctlbyname("vm.swapusage", &buf, &outSize, nil, 0) == 0, outSize > 0 else {
            return (Int(level), 0, 0)
        }

        let (totalBytes, usedBytes) = SwapParser.usage(from: buf, size: outSize)
        let ratio: Double = totalBytes > 0 ? min(1.0, Double(usedBytes) / Double(totalBytes)) : 0
        return (Int(level), usedBytes, ratio)
    }

    // MARK: - Thermal

    private static func readThermalState() -> Int {
        Int(ProcessInfo.processInfo.thermalState.rawValue)
    }

    // MARK: - GPU

    private static func readGPU() async -> Double {
        let raw = await StatsHelper.shared.query("gpu")
        return min(1.0, (Double(raw) ?? 0) / 100.0)
    }

    /// One "all" request to the resident helper returns GPU percent,
    /// milliwatts, and the read/write byte counters on a single line, so
    /// the pipe round-trip and IOKit pass happen once per tick instead of
    /// one round-trip per metric.
    private static func readAll() async -> (gpu: Double, power: Double, disk: (UInt64, UInt64)?) {
        let raw = await StatsHelper.shared.query("all")
        let parts = raw.split(separator: " ")
        guard parts.count >= 4,
              let gpuPct = Double(parts[0]),
              let mw = Double(parts[1]),
              let read = UInt64(parts[2]),
              let write = UInt64(parts[3])
        else { return (0, 0, nil) }
        return (min(1.0, gpuPct / 100.0), mw / 1000.0, (read, write))
    }

    // MARK: - Power

    private static func readPower() async -> Double {
        // The helper reports milliwatts (AppleSmartBattery SystemLoad).
        let raw = await StatsHelper.shared.query("power")
        return (Double(raw) ?? 0) / 1000.0
    }

    // MARK: - Disk

    private mutating func readDisk(_ bytes: (UInt64, UInt64)?) -> (Double, Double) {
        guard let (r, w) = bytes else {
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

    private static func readDiskBytes() async -> (UInt64, UInt64)? {
        let raw = await StatsHelper.shared.query("disk")
        let parts = raw.split(separator: " ")
        guard parts.count == 2,
              let r = UInt64(parts[0]),
              let w = UInt64(parts[1]) else { return nil }
        return (r, w)
    }

    // MARK: - Network Bytes

    private mutating func readNetwork() -> (Double, Double) {
        guard let (tx, rx) = Self.readNetworkBytes(interface: cachedInterfaceName) else {
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

    // MARK: - Connection type + RSSI + primary interface

    /// Resolves the connection kind and the interface the routing stack
    /// actually uses (PrimaryInterface), so byte counters and the label
    /// always refer to the same interface. VPN and tethering services carry
    /// no Hardware key, so they are classified by their Type / name.
    private static func readConnectionInfo() -> (type: String, rssi: Int, interface: String) {
        guard let store = SCDynamicStoreCreate(nil, "Semono" as CFString, nil, nil) else {
            return ("---", 0, "en0")
        }
        guard let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
              let primaryID = global["PrimaryService"] as? String
        else {
            return ("---", 0, "en0")
        }
        let primaryInterface = global["PrimaryInterface"] as? String ?? "en0"

        let svc = SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\(primaryID)/Interface" as CFString) as? [String: Any]
        let hardware = svc?["Hardware"] as? String ?? ""
        let type = svc?["Type"] as? String ?? ""
        let userDefinedName = (svc?["UserDefinedName"] as? String) ?? ""
        let device = svc?["DeviceName"] as? String ?? primaryInterface

        if hardware == "AirPort" {
            let rssi = CWWiFiClient.shared().interface()?.rssiValue() ?? 0
            return ("WiFi", rssi, device)
        }
        // iPhone tethering (USB / Bluetooth PAN) reports as an Ethernet-
        // style service; label it as its own kind instead of "Eth".
        if userDefinedName.range(of: "iPhone", options: .caseInsensitive) != nil {
            return ("iPhone", 0, device)
        }
        // VPN services (TUN-mode proxies etc.) carry Type == "VPN" and no
        // Hardware key; previously they matched nothing and showed "---".
        if type == "VPN" {
            return ("VPN", 0, device)
        }
        return ("Eth", 0, device)
    }

    // MARK: - Hardware Info (collected once)

    private static func readPhysicalMemory() -> UInt64 {
        var mem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &mem, &size, nil, 0)
        return mem
    }

    // MARK: - Frequency

    private static func readPerCoreFrequencies() -> [Double] {
        var freqs: [Double] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleARMCPU")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            if let props = IORegistryEntryCreateCFProperty(entry, "cpu-frequency" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() {
                var freq: UInt64 = 0
                switch props {
                case let number as CFNumber:
                    CFNumberGetValue(number, .sInt64Type, &freq)
                case let data as CFData where CFDataGetLength(data) >= 8:
                    CFDataGetBytes(data, CFRange(location: 0, length: 8), &freq)
                default:
                    break
                }
                freqs.append(Double(freq) / 1_000_000.0)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }

        return freqs
    }

    // MARK: - Shared helpers

    private static func readNetworkBytes(interface: String) -> (tx: UInt64, rx: UInt64)? {
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

    private static let kCPUStateMax    = Int32(4)
    private static let kCPUStateUser   = Int32(0)
    private static let kCPUStateSystem = Int32(1)
    private static let kCPUStateIdle   = Int32(2)
    private static let kCPUStateNice   = Int32(3)
}

// MARK: - Resident stats helper

/// Persistent client for the bundled `stats_helper` subprocess. A single
/// resident process serves GPU / power / disk readings over a line protocol
/// (request line in, response line out), replacing the previous per-tick
/// process spawns.
///
/// Requests are serialized (the sampler awaits each one). A request that
/// does not answer within the timeout terminates the helper; the next query
/// respawns it, so a hung helper recovers by itself and no worker thread is
/// ever blocked — responses arrive through the pipe's readability handler.
///
/// All state is guarded by `lock`. The readability handler is dispatched on
/// its own queue and may interleave with request submission, so it captures
/// the process it belongs to and only mutates state while that process is
/// still the current one — a late EOF from a replaced helper cannot clobber
/// a newer helper's pipes or steal its pending request.
private final class StatsHelper: @unchecked Sendable {
    static let shared = StatsHelper()

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.semono.app.statshelper", qos: .utility)
    private var process: Process?
    private var writeHandle: FileHandle?
    private var readHandle: FileHandle?
    private var pending: CheckedContinuation<String, Never>?
    private var pendingTimer: DispatchSourceTimer?
    private var buffer = Data()
    private let logger = Logger(subsystem: "com.semono.app", category: "stats_helper")
    private var warnedSpawn = false
    private var warnedHang = false

    private init() {}

    /// Sends one request line and returns the response line. Returns ""
    /// when the helper cannot be launched, times out, or dies.
    func query(_ name: String, timeout: TimeInterval = 2.0) async -> String {
        await withCheckedContinuation { cont in
            lock.lock()
            if process == nil || !(process?.isRunning ?? false) {
                spawnLocked()
            }
            guard let proc = process, proc.isRunning, pending == nil else {
                if process == nil {
                    warnOnce(flag: &warnedSpawn,
                             message: "stats_helper could not be launched; GPU/power/disk will read 0")
                }
                lock.unlock()
                cont.resume(returning: "")
                return
            }
            pending = cont

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + timeout)
            timer.setEventHandler { [weak self] in
                self?.handleTimeout(timer: timer)
            }
            pendingTimer = timer
            timer.resume()

            do {
                try writeHandle?.write(contentsOf: Data((name + "\n").utf8))
                lock.unlock()
            } catch {
                // The helper died between the running check and the write.
                // Drop the request and the timer; kill the helper so the
                // EOF handler frees the pipe state, and the next query
                // respawns a fresh process.
                pendingTimer = nil
                pending = nil
                lock.unlock()
                timer.cancel()
                killHelper(proc)
                cont.resume(returning: "")
            }
        }
    }

    /// Kills the helper so no orphan remains after the app quits. Resumes
    /// any in-flight request with "".
    func shutdown() {
        lock.lock()
        let proc = process
        process = nil
        if let h = readHandle { h.readabilityHandler = nil }
        readHandle = nil
        writeHandle = nil
        buffer = Data()
        let cont = pending
        pending = nil
        let timer = pendingTimer
        pendingTimer = nil
        lock.unlock()
        timer?.cancel()
        killHelper(proc)
        cont?.resume(returning: "")
    }

    /// Timeout path: abandon the request and kill the helper. The EOF
    /// handler observes the termination and frees the pipe state. A stale
    /// timer (a response arrived first, or a newer request owns the slot)
    /// is ignored.
    private func handleTimeout(timer: DispatchSourceTimer) {
        lock.lock()
        guard pendingTimer === timer else {
            lock.unlock()
            return
        }
        pendingTimer = nil
        let proc = process
        let cont = pending
        let alive = (proc?.isRunning ?? false) && cont != nil
        if alive {
            pending = nil
        }
        lock.unlock()
        timer.cancel()
        guard alive else { return }
        warnOnce(flag: &warnedHang,
                 message: "stats_helper did not answer in time; restarting it")
        killHelper(proc)
        cont?.resume(returning: "")
    }

    private func spawnLocked() {
        if let h = readHandle { h.readabilityHandler = nil }
        readHandle = nil
        writeHandle = nil
        buffer = Data()

        let name = "stats_helper"
        var url = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/\(name)")
        if !FileManager.default.fileExists(atPath: url.path) {
            // Debug runs (`swift run`) place the helper next to the executable.
            url = Bundle.main.bundleURL.appendingPathComponent(name)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            process = nil
            return
        }

        let task = Process()
        task.executableURL = url
        let out = Pipe()
        let input = Pipe()
        task.standardOutput = out
        task.standardInput = input
        do {
            try task.run()
        } catch {
            process = nil
            return
        }

        process = task
        // Reaps the child on exit so a killed helper never lingers as a
        // zombie (the pipe's EOF is delivered by the kernel regardless).
        task.terminationHandler = { proc in
            proc.waitUntilExit()
        }
        writeHandle = input.fileHandleForWriting
        readHandle = out.fileHandleForReading
        warnedSpawn = false
        warnedHang = false
        readHandle?.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            self.lock.lock()
            if data.isEmpty {
                // EOF: the helper died (or was terminated). Only tear down
                // if this handle still belongs to the current process; a
                // stale EOF from a replaced helper must not disturb the
                // newer one or its pending request.
                guard let proc = self.process, proc === task else {
                    self.lock.unlock()
                    return
                }
                handle.readabilityHandler = nil
                self.process = nil
                self.readHandle = nil
                self.writeHandle = nil
                self.buffer = Data()
                let cont = self.pending
                self.pending = nil
                let timer = self.pendingTimer
                self.pendingTimer = nil
                self.lock.unlock()
                timer?.cancel()
                cont?.resume(returning: "")
                return
            }
            self.buffer.append(data)
            if let nl = self.buffer.firstIndex(of: 0x0A) {
                let line = String(data: Data(self.buffer[..<nl]), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                self.buffer = Data(self.buffer[(nl + 1)...])
                let cont = self.pending
                self.pending = nil
                let timer = self.pendingTimer
                self.pendingTimer = nil
                self.lock.unlock()
                timer?.cancel()
                cont?.resume(returning: line)
            } else {
                self.lock.unlock()
            }
        }
    }

    /// Terminates the helper. The spawn-time `terminationHandler` reaps it.
    private func killHelper(_ proc: Process?) {
        guard let proc, proc.isRunning else { return }
        proc.terminate()
    }

    private func warnOnce(flag: inout Bool, message: String) {
        guard !flag else { return }
        flag = true
        logger.error("\(message, privacy: .public)")
    }
}

private typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
