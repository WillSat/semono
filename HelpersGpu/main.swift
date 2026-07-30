import Foundation
import IOKit

var iter: io_iterator_t = 0
guard IOServiceGetMatchingServices(0, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS,
      iter != 0
else { print("0"); exit(0) }
defer { IOObjectRelease(iter) }

let svc = IOIteratorNext(iter)
guard svc != 0 else { print("0"); exit(0) }
defer { IOObjectRelease(svc) }

var props: Unmanaged<CFMutableDictionary>?
guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let dict = props?.takeRetainedValue() as? [String: Any]
else { print("0"); exit(0) }

if let perfStats = dict["PerformanceStatistics"] as? [String: Any],
   let gpuUtil = perfStats["Device Utilization %"] as? Int {
    print(gpuUtil)
} else {
    print("0")
}
