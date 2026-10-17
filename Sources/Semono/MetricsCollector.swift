import Foundation
import Darwin
import Dispatch
import SystemConfiguration
import CoreWLAN
import Network
import os

@MainActor
final class MetricsCollector: ObservableObject {
    // A nil value means "not available / not measured yet". The UI renders it
    // as a dash; it is never coerced to a plausible-looking zero.
    @Published var gpuUsage: Double?
    @Published var cpuUsage: Double?
    @Published var memoryUsage: Double?
    @Published var powerUsage: Double?
    @Published var downloadSpeed: Double?
    @Published var uploadSpeed: Double?
    @Published var networkType: String?
    @Published var wifiRSSI: Int?
    @Published var memoryPressureLevel: Int?
    @Published var swapBytes: UInt64?
    @Published var swapRatio: Double?
    @Published var diskReadSpeed: Double?
    @Published var diskWriteSpeed: Double?
    @Published var thermalState: Int?

    init() {}

    private var updateTask: Task<Void, Never>?
    /// Cancels the current wait between ticks so a scope change is picked up at
    /// once instead of up to a refresh interval later.
    private var tickSleep: Task<Void, Never>?
    /// What the loop is allowed to read right now; see `SamplingScope`.
    private var scope: SamplingScope = .full
    /// Set by sleep/wake/manual reset; consumed by the sampling loop before the
    /// next tick so a long suspension is not averaged into one throughput read.
    private var resetBaselinesNextTick = false
    /// Set by NWPathMonitor when the interface path changes; forces the next
    /// tick to re-resolve the primary service before reading counters.
    private var networkRefreshNextTick = false
    private let pathMonitor = NWPathMonitor()

    /// Runs one sampling loop for the lifetime of the app. The scope is read
    /// afresh every tick, so the loop is never torn down and rebuilt when the
    /// HUD sleeps or wakes — a rebuild would reset the rate baselines and the
    /// slow-moving sensor caches along with it.
    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                self?.networkRefreshNextTick = true
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.semono.app.network-path", qos: .utility))

        updateTask = Task { [weak self] in
            var sampler = Sampler()
            var lastScope: SamplingScope?
            var lastDemand: SamplingDemand?
            while !Task.isCancelled {
                guard let self else { return }
                let scope = self.scope
                let demand = SamplingDemand.current()
                // Rates are deltas between consecutive reads. Across a sleep,
                // a Space change, a settings change, or a HUD wake they would
                // span a different measurement window, so the first tick
                // back re-baselines rather than averaging over the gap.
                if let lastScope, lastScope != scope {
                    sampler.resetRateBaselines()
                }
                if let lastDemand, lastDemand != demand {
                    sampler.resetRateBaselines()
                }
                if self.resetBaselinesNextTick {
                    sampler.resetRateBaselines()
                    self.resetBaselinesNextTick = false
                }
                if self.networkRefreshNextTick {
                    sampler.invalidateConnectionCache()
                    self.networkRefreshNextTick = false
                }
                lastScope = scope
                lastDemand = demand

                let sample = await sampler.sampleOnce(flags: .forTick(scope: scope, demand: demand))
                self.apply(sample)
                await self.waitForNextTick()
            }
        }
    }

    func stop() {
        tickSleep?.cancel()
        tickSleep = nil
        updateTask?.cancel()
        updateTask = nil
        pathMonitor.cancel()
        StatsHelper.shared.shutdown()
    }

    /// Puts the loop to sleep or wakes it. Driven purely by whether the HUD is
    /// on screen; a no-op while the scope is unchanged.
    func setScope(_ scope: SamplingScope) {
        guard scope != self.scope else { return }
        self.scope = scope
        tickSleep?.cancel()
    }

    /// Drops the rate baselines before the next tick. Called by the AppDelegate
    /// after system wake, and available for tests/future clock-change hooks.
    func resetRateBaselinesSoon() {
        resetBaselinesNextTick = true
        tickSleep?.cancel()
    }

    /// Sleeps out one refresh interval, cut short when the scope changes so a
    /// HUD coming back on screen is repainted immediately instead of showing
    /// what it last saw until the next scheduled tick.
    private func waitForNextTick() async {
        let interval = Double(SettingsStore.shared.refreshInterval)
        // Tolerance lets the kernel coalesce this wakeup with other system
        // timers instead of the process waking alone on every tick; the HUD
        // needs no tick-level precision.
        let tick = Task {
            do {
                try await Task.sleep(
                    for: .seconds(interval),
                    tolerance: .seconds(min(interval * 0.2, 1.0))
                )
            } catch {
                // Cancelled because the scope changed: sample again right away.
            }
        }
        tickSleep = tick
        await tick.value
        tickSleep = nil
    }

    /// Publishes a sample. @Published fires only on actual value changes so
    /// the HUD does not re-render when the metrics are static.
    private func apply(_ s: Sampler.Sample) {
        if gpuUsage != s.gpuUsage { gpuUsage = s.gpuUsage }
        if cpuUsage != s.cpuUsage { cpuUsage = s.cpuUsage }
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
    }
}

// MARK: - Sampling scope

/// What the sampling loop is allowed to read.
///
/// The menu bar readout is on screen in every Space — including the full-screen
/// Spaces the overlay itself is excluded from — so its metric is sampled in
/// both scopes. HUD columns are only worth reading while the HUD is on screen.
enum SamplingScope: Equatable {
    /// HUD on screen: columns and the menu bar metric.
    case full
    /// HUD not on screen: the menu bar metric alone.
    case statusBarOnly
}

/// What the UI currently asks to see, independent of whether the HUD is asleep.
/// Read from the settings at the top of every tick, or built by hand in tests.
struct SamplingDemand: Equatable {
    var computeColumn = true
    var memoryColumn = true
    var storageColumn = true
    var networkColumn = true
    var statusBarMetric: StatusBarMetric = .cpu

    @MainActor
    static func current() -> SamplingDemand {
        let s = SettingsStore.shared
        return SamplingDemand(
            computeColumn: s.showComputeColumn,
            memoryColumn: s.showMemoryColumn,
            storageColumn: s.showStorageColumn,
            networkColumn: s.showNetworkColumn,
            statusBarMetric: StatusBarMetric(rawValue: s.statusBarMetric) ?? .cpu
        )
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
        var collectThermal: Bool

        /// One tick's work. Sleeping (`statusBarOnly`) reads exactly the metric
        /// the menu bar shows and nothing else.
        static func forTick(scope: SamplingScope, demand: SamplingDemand) -> Flags {
            let columns = scope == .full
            let bar = demand.statusBarMetric
            return Flags(
                collectGPU: (columns && demand.computeColumn) || bar == .gpu,
                collectCPU: (columns && demand.computeColumn) || bar == .cpu,
                collectMemory: (columns && demand.memoryColumn) || bar == .memory,
                collectPower: (columns && demand.computeColumn) || bar == .pwr,
                collectStorage: columns && demand.storageColumn,
                collectNetwork: columns && demand.networkColumn,
                collectThermal: columns && demand.storageColumn
            )
        }
    }

    struct Sample: Sendable, Equatable {
        var gpuUsage: Double?
        var cpuUsage: Double?
        var memoryUsage: Double?
        var powerUsage: Double?
        var downloadSpeed: Double?
        var uploadSpeed: Double?
        var networkType: String?
        var wifiRSSI: Int?
        var memoryPressureLevel: Int?
        var swapBytes: UInt64?
        var swapRatio: Double?
        var diskReadSpeed: Double?
        var diskWriteSpeed: Double?
        var thermalState: Int?
    }

    // Slow-moving readings are cached and refreshed on longer intervals. All
    // instants are monotonic nanoseconds, never wall-clock Date values.
    private static let connCacheInterval: UInt64 = 15_000_000_000
    private static let swapCacheInterval: UInt64 = 10_000_000_000

    private var prevCPULoad: CPULoad?
    private var prevNetRx: UInt64 = 0
    private var prevNetTx: UInt64 = 0
    private var prevNetTime: UInt64 = 0
    private var prevNetInterface: String?
    private var hasPrevNet: Bool = false
    private var prevDiskReadBytes: UInt64 = 0
    private var prevDiskWriteBytes: UInt64 = 0
    private var prevDiskTime: UInt64 = 0
    private var hasPrevDisk: Bool = false
    private var connCacheTime: UInt64 = 0
    private var cachedConnType: String?
    private var cachedRSSI: Int?
    private var cachedInterfaceName: String?
    private var swapCacheTime: UInt64 = 0
    private var cachedSwap: (Int?, UInt64?, Double?) = (nil, nil, nil)
    private var warnedPressureSysctl = false
    private static let logger = Logger(subsystem: "com.semono.app", category: "sampler")

    /// Drops the counters that throughput and CPU percentages are measured
    /// against, so the next sample re-baselines them instead of dividing a long
    /// silence by one short interval. Cache timestamps are cleared too: after a
    /// wake, the connection/swap readings may have changed while the process
    /// was suspended.
    mutating func resetRateBaselines() {
        prevCPULoad = nil
        hasPrevNet = false
        prevNetInterface = nil
        hasPrevDisk = false
        connCacheTime = 0
        cachedConnType = nil
        cachedRSSI = nil
        cachedInterfaceName = nil
        swapCacheTime = 0
        cachedSwap = (nil, nil, nil)
    }

    /// Forces the next network sample to re-resolve the primary interface
    /// before reading counters. Called while the sampler is otherwise idle
    /// between ticks; no need to reset CPU/disk baselines.
    mutating func invalidateConnectionCache() {
        connCacheTime = 0
        cachedConnType = nil
        cachedRSSI = nil
        cachedInterfaceName = nil
        hasPrevNet = false
        prevNetInterface = nil
    }

    mutating func sampleOnce(flags: Flags) async -> Sample {
        var s = Sample()
        let now = Self.monotonicNow()

        let wantsGPU = flags.collectGPU
        let wantsPower = flags.collectPower
        let wantsDisk = flags.collectStorage
        // When two or more helper-backed metrics are live, a single "all"
        // request serves them in one pipe round-trip and one IOKit pass.
        // A lone metric keeps its dedicated query; the resident helper makes
        // per-tick reads cheap, so power/disk are never staggered.
        if (wantsGPU ? 1 : 0) + (wantsPower ? 1 : 0) + (wantsDisk ? 1 : 0) >= 2 {
            let (gpu, power, disk) = await Self.readAll()
            if wantsGPU { s.gpuUsage = gpu }
            if wantsPower { s.powerUsage = power }
            if wantsDisk {
                (s.diskReadSpeed, s.diskWriteSpeed) = readDisk(disk, now: now)
            }
        } else {
            if wantsGPU {
                s.gpuUsage = await Self.readGPU()
            }
            if wantsPower {
                s.powerUsage = await Self.readPower()
            }
            if wantsDisk {
                (s.diskReadSpeed, s.diskWriteSpeed) = readDisk(await Self.readDiskBytes(), now: now)
            }
        }
        if flags.collectCPU {
            s.cpuUsage = readCPU()
        }

        if flags.collectMemory {
            s.memoryUsage = Self.readMemory()
            if Self.intervalElapsed(now: now, since: swapCacheTime, interval: Self.swapCacheInterval) {
                cachedSwap = readSwapAndPressure()
                swapCacheTime = now
            }
            (s.memoryPressureLevel, s.swapBytes, s.swapRatio) = cachedSwap
        }

        if flags.collectThermal {
            s.thermalState = Self.readThermalState()
        }

        if flags.collectNetwork {
            // Resolve the interface before reading counters. The old order
            // read the default "en0" baseline first and only then discovered
            // the real primary interface, so the second tick diffed counters
            // across two different interfaces.
            if connCacheTime == 0
                || !hasPrevNet
                || cachedInterfaceName == nil
                || Self.intervalElapsed(now: now, since: connCacheTime, interval: Self.connCacheInterval)
            {
                let info = Self.readConnectionInfo()
                cachedConnType = info.type
                cachedRSSI = info.rssi
                cachedInterfaceName = info.interface
                connCacheTime = now
            }
            (s.downloadSpeed, s.uploadSpeed) = readNetwork(now: now)
            s.networkType = cachedConnType
            s.wifiRSSI = cachedRSSI
        }

        return s
    }

    // MARK: - CPU

    private mutating func readCPU() -> Double? {
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
        guard result == KERN_SUCCESS, cpuInfo != nil else {
            prevCPULoad = nil
            return nil
        }

        let cpuCount = Int(numCPUs)
        // The kernel promises cpuCount * kCPUStateMax entries; if a future
        // build ever returns fewer, bail before indexing past the buffer.
        guard Int(numCpuInfo) >= cpuCount * Int(Self.kCPUStateMax) else {
            Self.releaseCpuInfo(cpuInfo, count: numCpuInfo)
            prevCPULoad = nil
            return nil
        }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        var nice: UInt64 = 0

        for i in 0..<cpuCount {
            let base = Int(Self.kCPUStateMax) * i
            user += UInt64(UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateUser))]))
            system += UInt64(UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateSystem))]))
            idle += UInt64(UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateIdle))]))
            nice += UInt64(UInt32(bitPattern: cpuInfo[Int(base + Int(Self.kCPUStateNice))]))
        }

        Self.releaseCpuInfo(cpuInfo, count: numCpuInfo)

        let current = CPULoad(user: user, system: system, nice: nice, idle: idle)
        let aggregate = CPUUsage.fraction(previous: prevCPULoad, current: current)
        prevCPULoad = current
        return aggregate
    }

    // MARK: - Memory

    private static let pageSize = Double(sysconf(Int32(_SC_PAGESIZE)))
    private static let totalMemory: Double = Double(readPhysicalMemory())

    private static func readMemory() -> Double? {
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

        // Approximates Activity Monitor's "App + Wired + Compressed": app
        // pages are the internal (non-file-backed) pages minus the purgeable
        // ones, instead of the whole active set which over-counts reclaimable
        // file cache pages.
        let app        = (Double(info.internal_page_count) - Double(info.purgeable_count)) * Self.pageSize
        let wired      = Double(info.wire_count) * Self.pageSize
        let compressed = Double(info.compressor_page_count) * Self.pageSize
        let used = max(0, app) + wired + compressed

        guard Self.totalMemory > 0 else { return nil }
        return min(1.0, used / Self.totalMemory)
    }

    // MARK: - Memory Pressure + Swap

    private mutating func readSwapAndPressure() -> (pressure: Int?, swapBytes: UInt64?, swapRatio: Double?) {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let pressure: Int?
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            pressure = MemoryPressure.level(fromRaw: Int(level))
        } else {
            pressure = nil
            if !warnedPressureSysctl {
                warnedPressureSysctl = true
                Self.logger.error("kern.memorystatus_vm_pressure_level read failed; pressure will read unavailable")
            }
        }

        var swapSize = 0
        sysctlbyname("vm.swapusage", nil, &swapSize, nil, 0)
        guard swapSize > 0 else { return (pressure, nil, nil) }

        var buf = [CChar](repeating: 0, count: swapSize)
        var outSize = swapSize
        guard sysctlbyname("vm.swapusage", &buf, &outSize, nil, 0) == 0, outSize > 0 else {
            return (pressure, nil, nil)
        }

        let (totalBytes, usedBytes) = SwapParser.usage(from: buf, size: outSize)
        let ratio: Double? = totalBytes > 0 ? min(1.0, Double(usedBytes) / Double(totalBytes)) : 0
        return (pressure, usedBytes, ratio)
    }

    // MARK: - Thermal

    private static func readThermalState() -> Int {
        Int(ProcessInfo.processInfo.thermalState.rawValue)
    }

    // MARK: - GPU

    private static func readGPU() async -> Double? {
        let raw = await StatsHelper.shared.query("gpu")
        guard let percent = HelperProtocol.double(raw) else { return nil }
        return min(1.0, max(0, percent / 100.0))
    }

    /// One "all" request to the resident helper returns GPU percent,
    /// milliwatts, and the read/write byte counters on a single line, so
    /// the pipe round-trip and IOKit pass happen once per tick instead of
    /// one round-trip per metric. Each field can independently be `na`.
    private static func readAll() async -> (gpu: Double?, power: Double?, disk: (UInt64, UInt64)?) {
        let raw = await StatsHelper.shared.query("all")
        guard let fields = HelperProtocol.fields(raw, count: 4) else {
            return (nil, nil, nil)
        }
        let gpu = HelperProtocol.double(fields[0]).map { min(1.0, max(0, $0 / 100.0)) }
        let power = HelperProtocol.double(fields[1]).map { max(0, $0 / 1000.0) }
        let read = HelperProtocol.uint64(fields[2])
        let write = HelperProtocol.uint64(fields[3])
        let disk: (UInt64, UInt64)? = (read != nil && write != nil) ? (read!, write!) : nil
        return (gpu, power, disk)
    }

    // MARK: - Power

    private static func readPower() async -> Double? {
        // The helper reports milliwatts (AppleSmartBattery SystemLoad), or
        // `na` on machines without a battery / telemetry key.
        let raw = await StatsHelper.shared.query("power")
        return HelperProtocol.double(raw).map { max(0, $0 / 1000.0) }
    }

    // MARK: - Disk

    private mutating func readDisk(_ bytes: (UInt64, UInt64)?, now: UInt64) -> (Double?, Double?) {
        guard let (r, w) = bytes else {
            // Sampling failed (helper down): drop the baseline so the next
            // reading re-baselines instead of reporting a rate that includes
            // the downtime.
            hasPrevDisk = false
            return (nil, nil)
        }

        guard hasPrevDisk else {
            prevDiskReadBytes = r; prevDiskWriteBytes = w; prevDiskTime = now
            hasPrevDisk = true
            return (nil, nil)
        }

        guard let dt = RateMath.seconds(from: prevDiskTime, to: now),
              let readSpeed = RateMath.bytesPerSecond(previous: prevDiskReadBytes, current: r, seconds: dt),
              let writeSpeed = RateMath.bytesPerSecond(previous: prevDiskWriteBytes, current: w, seconds: dt)
        else {
            hasPrevDisk = false
            return (nil, nil)
        }

        prevDiskReadBytes = r; prevDiskWriteBytes = w; prevDiskTime = now
        return (readSpeed, writeSpeed)
    }

    private static func readDiskBytes() async -> (UInt64, UInt64)? {
        let raw = await StatsHelper.shared.query("disk")
        guard let fields = HelperProtocol.fields(raw, count: 2),
              let r = HelperProtocol.uint64(fields[0]),
              let w = HelperProtocol.uint64(fields[1])
        else { return nil }
        return (r, w)
    }

    // MARK: - Network Bytes

    private mutating func readNetwork(now: UInt64) -> (Double?, Double?) {
        guard let interface = cachedInterfaceName,
              let counters = NetworkCounters.read(interfaceName: interface)
        else {
            // Sampling failed or there is no primary service: drop the
            // baseline so a later reading cannot span the outage.
            hasPrevNet = false
            prevNetInterface = nil
            return (nil, nil)
        }

        guard hasPrevNet, prevNetInterface == interface else {
            prevNetRx = counters.receivedBytes
            prevNetTx = counters.sentBytes
            prevNetTime = now
            prevNetInterface = interface
            hasPrevNet = true
            return (nil, nil)
        }

        guard let dt = RateMath.seconds(from: prevNetTime, to: now),
              let down = RateMath.bytesPerSecond(previous: prevNetRx, current: counters.receivedBytes, seconds: dt),
              let up = RateMath.bytesPerSecond(previous: prevNetTx, current: counters.sentBytes, seconds: dt)
        else {
            // A counter regression means the interface was reset or replaced;
            // the next tick establishes a fresh baseline.
            hasPrevNet = false
            prevNetInterface = nil
            return (nil, nil)
        }

        prevNetRx = counters.receivedBytes; prevNetTx = counters.sentBytes; prevNetTime = now
        return (down, up)
    }

    // MARK: - Connection type + RSSI + primary interface

    /// Resolves the connection kind and the interface the routing stack
    /// actually uses (PrimaryInterface), so byte counters and the label
    /// always refer to the same interface. VPN and tethering services carry
    /// no Hardware key, so they are classified by their Type / name.
    private static func readConnectionInfo() -> (type: String?, rssi: Int?, interface: String?) {
        guard let store = SCDynamicStoreCreate(nil, "Semono" as CFString, nil, nil) else {
            return (nil, nil, nil)
        }
        // Prefer IPv4, but an IPv6-only network still has a primary service
        // and interface; falling straight through to "Offline" would hide a
        // working network and its counters.
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let ipv6 = ipv4 == nil
            ? SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv6" as CFString) as? [String: Any]
            : nil
        guard let global = ipv4 ?? ipv6,
              let primaryID = global["PrimaryService"] as? String,
              let primaryInterface = global["PrimaryInterface"] as? String,
              !primaryInterface.isEmpty
        else {
            return ("Offline", nil, nil)
        }

        let svc = SCDynamicStoreCopyValue(store, "Setup:/Network/Service/\(primaryID)/Interface" as CFString) as? [String: Any]
        let hardware = svc?["Hardware"] as? String ?? ""
        let type = svc?["Type"] as? String ?? ""
        let userDefinedName = (svc?["UserDefinedName"] as? String) ?? ""
        let device = (svc?["DeviceName"] as? String) ?? primaryInterface

        if hardware == "AirPort" {
            let rawRSSI = CWWiFiClient.shared().interface()?.rssiValue()
            let rssi = (rawRSSI ?? 0) == 0 ? nil : rawRSSI
            return ("WiFi", rssi, device)
        }
        // iPhone tethering (USB / Bluetooth PAN) reports as an Ethernet-
        // style service; label it as its own kind instead of "Eth".
        if userDefinedName.range(of: "iPhone", options: .caseInsensitive) != nil {
            return ("iPhone", nil, device)
        }
        // VPN services (TUN-mode proxies etc.) carry Type == "VPN" and no
        // Hardware key; previously they matched nothing and showed "---".
        if type == "VPN" {
            return ("VPN", nil, device)
        }
        return ("Eth", nil, device)
    }

    // MARK: - Hardware Info (collected once)

    private static func readPhysicalMemory() -> UInt64 {
        var mem: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.memsize", &mem, &size, nil, 0) != 0 {
            // Runs once (static `totalMemory`); a failure would otherwise
            // silently pin the memory percentage at 0.
            logger.error("hw.memsize read failed; memory percentage will read unavailable")
        }
        return mem
    }

    // MARK: - Shared helpers

    private static func monotonicNow() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    private static func intervalElapsed(now: UInt64, since: UInt64, interval: UInt64) -> Bool {
        guard since != 0, now >= since else { return since == 0 }
        return now - since >= interval
    }

    private static func releaseCpuInfo(_ info: processor_info_array_t, count: mach_msg_type_number_t) {
        let size = vm_size_t(MemoryLayout<integer_t>.stride * Int(count))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
    }

    private static let kCPUStateMax    = Int32(4)
    private static let kCPUStateUser   = Int32(0)
    private static let kCPUStateSystem = Int32(1)
    private static let kCPUStateIdle   = Int32(2)
    private static let kCPUStateNice   = Int32(3)
}

private typealias processor_info_array_t = UnsafeMutablePointer<integer_t>
