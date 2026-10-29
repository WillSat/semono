import Foundation
import Testing
@testable import Semono

struct MemoryDetailTests {
    @Test func usedAndSwapFractions() {
        let snapshot = MemoryDetailSnapshot(
            totalBytes: 16_000_000_000,
            appBytes: 4_000_000_000,
            wiredBytes: 2_000_000_000,
            compressedBytes: 1_000_000_000,
            cachedBytes: 5_000_000_000,
            freeBytes: 4_000_000_000,
            swapUsedBytes: 1_000_000_000,
            swapTotalBytes: 2_000_000_000,
            pressureLevel: 1,
            processes: [],
            timestamp: Date()
        )

        #expect(snapshot.usedBytes == 7_000_000_000)
        #expect(abs(snapshot.usedFraction - 0.4375) < 0.0001)
        #expect(abs(snapshot.swapFraction - 0.5) < 0.0001)
        #expect(snapshot.categories.count == 5)
        #expect(snapshot.categories.reduce(0) { $0 + $1.bytes } == snapshot.totalBytes)
    }

    @Test func missingSwapIsUnavailable() {
        let snapshot = MemoryDetailSnapshot(
            totalBytes: 16_000_000_000,
            appBytes: 0,
            wiredBytes: 0,
            compressedBytes: 0,
            cachedBytes: 0,
            freeBytes: 16_000_000_000,
            swapUsedBytes: nil,
            swapTotalBytes: nil,
            pressureLevel: nil,
            processes: [],
            timestamp: Date()
        )
        #expect(snapshot.swapFraction == 0)
        #expect(snapshot.usedFraction == 0)
    }
}
