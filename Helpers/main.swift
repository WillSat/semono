import Foundation
import IOKit
import Darwin

// Resident stats daemon. Reads one request per line from stdin:
//
//     <id> gpu    -> "<id> gpu 2 0..100"              (percent, or na)
//     <id> power  -> "<id> power 2 milliwatts"         (or na)
//     <id> disk   -> "<id> disk 2 readBytes writeBytes" (or na na)
//     <id> all    -> "<id> all 2 gpuPercent mW readBytes writeBytes"
//     <id> hello  -> "<id> hello 2"
//
// Values are numbers or the literal "na". The id and protocol version are part
// of every response: the app can tell a late answer to a cancelled request
// from the answer to the current one, and an app/helper version mismatch fails
// visibly instead of being silently parsed as zeros.
//
// Prints exactly one response line and flushes. Exits when stdin closes (the
// parent app quitting closes the pipe, so the helper self-cleans).

// If the parent closes stdout while stdin is still open, print() must fail
// with an error instead of SIGPIPE killing this process — a signal death
// would read as a spurious EOF plus a respawn backoff on the parent side.
signal(SIGPIPE, SIG_IGN)

let protocolVersion = 2

// MARK: - GPU

func gpuUsage() -> String {
    guard let dict = firstServiceProperties(matchingService: "IOAccelerator"),
          let perfStats = dict["PerformanceStatistics"] as? [String: Any],
          let gpuUtil = perfStats["Device Utilization %"] as? NSNumber
    else { return "na" }
    return gpuUtil.stringValue
}

// MARK: - Power

/// Apple Silicon system power draw in milliwatts (verified against live
/// readings: idle laptops report a few thousand mW). Machines without an
/// AppleSmartBattery — desktops, some Intel models — return nil, which the
/// app renders as unavailable rather than 0 W.
func powerLoad() -> String? {
    guard let dict = firstServiceProperties(matchingService: "AppleSmartBattery"),
          let tele = dict["PowerTelemetryData"] as? [String: Any],
          let load = tele["SystemLoad"] as? NSNumber
    else { return nil }
    return load.stringValue
}

/// Power draw moves slowly, so it is cached briefly; at the 1 s refresh tier
/// this halves the IOKit registry walks. GPU stays fresh (it flickers too
/// fast to cache) and disk stays fresh (the parent derives rates from the
/// counters' deltas, so a cached counter would misreport throughput).
/// The request loop below is strictly single-threaded, so the cache needs no
/// synchronization; top-level vars in a main file default to MainActor, so
/// opt out explicitly.
nonisolated(unsafe) var cachedPower = (value: "na", time: UInt64(0))

func powerLoadCached() -> String {
    let now = DispatchTime.now().uptimeNanoseconds
    if cachedPower.time != 0, now >= cachedPower.time,
       now - cachedPower.time < 2_000_000_000 {
        return cachedPower.value
    }
    let value = powerLoad() ?? "na"
    cachedPower = (value, now)
    return value
}

// MARK: - Disk

/// Sums Bytes (Read)/Bytes (Write) across every IOBlockStorageDriver so the
/// reading covers the whole system, not just the first drive. If no driver
/// exposes statistics, returns "na na" instead of "0 0": a real zero counter
/// is valid at boot, while a failed read must not reset the parent's baseline
/// and produce a spike on the next successful sample.
func diskBytes() -> String {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(0, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS,
          iterator != 0
    else { return "na na" }
    defer { IOObjectRelease(iterator) }

    var totalRead: UInt64 = 0
    var totalWrite: UInt64 = 0
    var found = false

    var entry = IOIteratorNext(iterator)
    while entry != 0 {
        defer { IOObjectRelease(entry) }
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = props?.takeRetainedValue() as? [String: Any],
           let stats = dict["Statistics"] as? [String: Any],
           let read = stats["Bytes (Read)"] as? NSNumber,
           let written = stats["Bytes (Write)"] as? NSNumber {
            totalRead += read.uint64Value
            totalWrite += written.uint64Value
            found = true
        }
        entry = IOIteratorNext(iterator)
    }
    return found ? "\(totalRead) \(totalWrite)" : "na na"
}

// MARK: - Shared

func firstServiceProperties(matchingService className: String) -> [String: Any]? {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(0, IOServiceMatching(className), &iterator) == KERN_SUCCESS,
          iterator != 0
    else { return nil }
    defer { IOObjectRelease(iterator) }

    let entry = IOIteratorNext(iterator)
    guard entry != 0 else { return nil }
    defer { IOObjectRelease(entry) }

    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any]
    else { return nil }
    return dict
}

// MARK: - Request loop

while let line = readLine() {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 2, let id = UInt64(parts[0]) else {
        // There is no id to echo, so a malformed request cannot be correlated;
        // the app will time out and restart the helper. Keep the line short.
        print("malformed")
        fflush(stdout)
        continue
    }
    let command = String(parts[1])
    switch command {
    case "gpu":
        print("\(id) gpu \(protocolVersion) \(gpuUsage())")
    case "power":
        print("\(id) power \(protocolVersion) \(powerLoadCached())")
    case "disk":
        print("\(id) disk \(protocolVersion) \(diskBytes())")
    case "all":
        print("\(id) all \(protocolVersion) \(gpuUsage()) \(powerLoadCached()) \(diskBytes())")
    case "hello":
        print("\(id) hello \(protocolVersion)")
    default:
        print("\(id) \(command) \(protocolVersion) err")
    }
    fflush(stdout)
}
