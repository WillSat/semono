import Foundation

/// Decodes the `vm.swapusage` sysctl output, which comes in two shapes:
///
/// - classic text blob on older macOS:
///   `total = 1024.00M  used = 235.06M  free = 788.94M  (encrypted)`
/// - the raw binary `struct xsw_usage` on macOS 26+:
///   `{ u64 total, u64 avail, u64 used, u32 pagesize, u32 encrypted }`
///
/// Text starts with 't'; the struct's first field's top byte is 0x00 for
/// any realistic swap size, so sniffing the first byte picks the decoder.
enum SwapParser {

    /// Returns (total, used) in bytes, or (0, 0) on malformed input.
    static func usage(from buf: [CChar], size: Int) -> (total: UInt64, used: UInt64) {
        guard size > 0 else { return (0, 0) }

        if buf[0] == 0x74 /* 't' */ {
            let str = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return (UInt64(parseTextField(str, key: "total")), UInt64(parseTextField(str, key: "used")))
        }

        guard size >= 32 else { return (0, 0) }
        let data = Data(bytes: buf, count: size)
        return (leUInt64(data, at: 0), leUInt64(data, at: 16))
    }

    /// Reads a little-endian UInt64 from a byte buffer. (Compiled by hand
    /// instead of `loadUnaligned` to dodge a Swift frontend crash.)
    static func leUInt64(_ data: Data, at offset: Int) -> UInt64 {
        guard offset + 8 <= data.count else { return 0 }
        var value: UInt64 = 0
        for i in 0..<8 {
            value |= UInt64(data[data.startIndex + offset + i]) << (8 * i)
        }
        return value
    }

    /// Parses a "key = <number><unit>" token out of the vm.swapusage text.
    /// Tolerant of decimal commas and unknown units (falls back to bytes),
    /// and never traps on malformed input.
    static func parseTextField(_ str: String, key: String) -> Double {
        guard let range = str.range(of: "\(key) = ") else { return 0 }
        let after = str[range.upperBound...]
        guard let token = after.split(separator: " ").first else { return 0 }
        let cleaned = String(token).replacingOccurrences(of: ",", with: ".")
        guard let numEnd = cleaned.firstIndex(where: { !$0.isNumber && $0 != "." }) else {
            return Double(cleaned) ?? 0
        }
        guard let value = Double(cleaned[..<numEnd]) else { return 0 }
        switch String(cleaned[numEnd...]).uppercased() {
        case "T": return value * 1_000_000_000_000
        case "G": return value * 1_000_000_000
        case "M": return value * 1_000_000
        case "K": return value * 1_000
        case "B": return value
        default:  return 0
        }
    }
}
