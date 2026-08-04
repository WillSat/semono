import Foundation
import Testing
@testable import Semono

/// Builds the raw bytes of `struct xsw_usage`:
/// { u64 total, u64 avail, u64 used, u32 pagesize, u32 encrypted }
private func xswUsage(total: UInt64, avail: UInt64, used: UInt64) -> [CChar] {
    func leBytes(_ v: UInt64) -> [CChar] {
        (0..<8).map { i in CChar(bitPattern: UInt8((v >> (8 * i)) & 0xFF)) }
    }
    return leBytes(total) + leBytes(avail) + leBytes(used)
        + [0x00, 0x40, 0, 0] // pagesize = 16384
        + [1, 0, 0, 0]       // encrypted = true
}

struct SwapParserTests {

    @Test func binaryStructDecodesCorrectly() {
        let buf = xswUsage(total: 1_073_741_824, avail: 827_260_928, used: 246_480_896)
        let (total, used) = SwapParser.usage(from: buf, size: buf.count)
        #expect(total == 1_073_741_824)
        #expect(used == 246_480_896)
    }

    @Test func truncatedBinaryStructIsRejected() {
        let full = xswUsage(total: 1_073_741_824, avail: 0, used: 0)
        let (total, used) = SwapParser.usage(from: Array(full.prefix(16)), size: 16)
        #expect(total == 0)
        #expect(used == 0)
    }

    @Test func classicTextBlobParses() {
        let text = "total = 1024.00M  used = 235.06M  free = 788.94M  (encrypted)"
        let buf = Array(text.utf8).map { CChar(bitPattern: $0) }
        let (total, used) = SwapParser.usage(from: buf, size: buf.count)
        #expect(total == 1_024_000_000)
        #expect(used == 235_060_000)
    }

    @Test func commaDecimalsParse() {
        let buf = Array("total = 1024,00M  used = 235,06M".utf8).map { CChar(bitPattern: $0) }
        let (total, used) = SwapParser.usage(from: buf, size: buf.count)
        #expect(total == 1_024_000_000)
        #expect(used == 235_060_000)
    }

    @Test func unknownUnitsFallBackToZero() {
        let buf = Array("total = 1024XB  used = 42XB".utf8).map { CChar(bitPattern: $0) }
        let (total, used) = SwapParser.usage(from: buf, size: buf.count)
        #expect(total == 0)
        #expect(used == 0)
    }

    @Test func emptyInputReturnsZero() {
        #expect(SwapParser.usage(from: [], size: 0) == (0, 0))
    }

    @Test func outOfBoundsReadReturnsZero() {
        let data = Data([0x01, 0x02, 0x03])
        #expect(SwapParser.leUInt64(data, at: 0) == 0)
    }
}
