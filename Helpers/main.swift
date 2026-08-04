import Foundation
import IOKit

// Resident stats daemon. Reads one request per line from stdin:
//
//     gpu    -> "0" ... "100"   (percent)
//     power  -> milliwatts      (AppleSmartBattery PowerTelemetryData SystemLoad)
//     disk   -> "readBytes writeBytes"  (aggregated across ALL block storage drivers)
//     all    -> "gpuPercent mW readBytes writeBytes"  (the three above in one pass)
//
// Prints exactly one response line and flushes. Exits when stdin closes
// (the parent app quitting closes the pipe, so the helper self-cleans).

// MARK: - GPU

func gpuUsage() -> String {
    guard let dict = firstServiceProperties(matchingService: "IOAccelerator"),
          let perfStats = dict["PerformanceStatistics"] as? [String: Any],
          let gpuUtil = perfStats["Device Utilization %"] as? NSNumber
    else { return "0" }
    return gpuUtil.stringValue
}

// MARK: - Power

/// Apple Silicon system power draw in milliwatts (verified against live
/// readings: idle laptops report a few thousand mW).
func powerLoad() -> String {
    guard let dict = firstServiceProperties(matchingService: "AppleSmartBattery"),
          let tele = dict["PowerTelemetryData"] as? [String: Any],
          let load = tele["SystemLoad"] as? NSNumber
    else { return "0" }
    return load.stringValue
}

// MARK: - Disk

/// Sums Bytes (Read)/Bytes (Write) across every IOBlockStorageDriver so the
/// reading covers the whole system, not just the first drive.
func diskBytes() -> String {
    var iterator: io_iterator_t = 0
    guard IOServiceGetMatchingServices(0, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS,
          iterator != 0
    else { return "0 0" }
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
    return found ? "\(totalRead) \(totalWrite)" : "0 0"
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
    switch line {
    case "gpu":   print(gpuUsage())
    case "power": print(powerLoad())
    case "disk":  print(diskBytes())
    case "all":   print("\(gpuUsage()) \(powerLoad()) \(diskBytes())")
    default:      print("0")
    }
    fflush(stdout)
}
