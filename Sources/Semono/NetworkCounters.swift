import Foundation
import Darwin

/// 64-bit per-interface byte counters from the interface MIB.
///
/// Two traps matter here:
///
/// 1. `getifaddrs` fills `ifa_data` with `struct if_data`, whose
///    `ifi_ibytes`/`ifi_obytes` are 32-bit. A 1 GbE link wraps that counter
///    every ~34 seconds, and a 10 GbE link every ~3.4 seconds.
/// 2. `NET_RT_IFLIST2` looks like the 64-bit replacement, but on the
///    macOS 27 build used to validate this code its `if_data64` counters were
///    still the low 32 bits (verified against `netstat -ib`). The per-interface
///    MIB, `net.link.generic.ifdata.<index>.general`, returns the real 64-bit
///    counters reported by netstat.
struct NetworkCounters: Sendable, Equatable {
    let interfaceIndex: UInt32
    let receivedBytes: UInt64
    let sentBytes: UInt64

    /// Reads the counters for a BSD interface name (e.g. `en0`, `utun3`).
    static func read(interfaceName: String) -> NetworkCounters? {
        let index = interfaceName.withCString { if_nametoindex($0) }
        guard index != 0 else { return nil }
        return read(interfaceIndex: index)
    }

    static func read(interfaceIndex: UInt32) -> NetworkCounters? {
        var mib: [Int32] = [
            CTL_NET,
            PF_LINK,
            NETLINK_GENERIC,
            IFMIB_IFDATA,
            Int32(bitPattern: interfaceIndex),
            IFDATA_GENERAL,
        ]
        var data = ifmibdata()
        var size = MemoryLayout<ifmibdata>.size
        guard sysctl(&mib, u_int(mib.count), &data, &size, nil, 0) == 0,
              size >= MemoryLayout<ifmibdata>.size
        else { return nil }
        return from(ifmib: data, interfaceIndex: interfaceIndex)
    }

    /// Converts one MIB record. Kept separate from the sysctl so the 64-bit
    /// field mapping can be tested without a live interface.
    static func from(ifmib data: ifmibdata, interfaceIndex: UInt32) -> NetworkCounters {
        NetworkCounters(
            interfaceIndex: interfaceIndex,
            receivedBytes: data.ifmd_data.ifi_ibytes,
            sentBytes: data.ifmd_data.ifi_obytes
        )
    }
}
