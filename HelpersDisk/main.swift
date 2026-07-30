import Foundation
import IOKit

var iter: io_iterator_t = 0
guard IOServiceGetMatchingServices(0, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS,
      iter != 0
else { print("0 0"); exit(0) }
defer { IOObjectRelease(iter) }

let svc = IOIteratorNext(iter)
guard svc != 0 else { print("0 0"); exit(0) }
defer { IOObjectRelease(svc) }

var props: Unmanaged<CFMutableDictionary>?
guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
      let dict = props?.takeRetainedValue() as? [String: Any]
else { print("0 0"); exit(0) }

if let stats = dict["Statistics"] as? [String: Any],
   let bytesRead = stats["Bytes (Read)"] as? Int,
   let bytesWritten = stats["Bytes (Write)"] as? Int {
    print("\(bytesRead) \(bytesWritten)")
} else {
    print("0 0")
}
