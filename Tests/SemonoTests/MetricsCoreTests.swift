import Foundation
import Darwin
import Testing
@testable import Semono

struct MemoryPressureTests {
    @Test func normalValuesMapToZero() {
        // macOS reports the dispatch note flags (normal = 1); 0 is the legacy
        // contiguous normal value. Neither may show a warning bar.
        #expect(MemoryPressure.level(fromRaw: 0) == 0)
        #expect(MemoryPressure.level(fromRaw: 1) == 0)
    }

    @Test func warningAndCriticalMapToTheTwoRaisedLevels() {
        // macOS exposes normal/warning/critical; 3 is the legacy urgent value
        // that the dispatch layer folds into warning.
        #expect(MemoryPressure.level(fromRaw: 2) == 1)
        #expect(MemoryPressure.level(fromRaw: 3) == 1)
        #expect(MemoryPressure.level(fromRaw: 4) == 2)
    }

    @Test func abbreviations() {
        #expect(MemoryPressure.abbreviation(for: 0) == "N")
        #expect(MemoryPressure.abbreviation(for: 1) == "W")
        #expect(MemoryPressure.abbreviation(for: 2) == "C")
        #expect(MemoryPressure.abbreviation(for: 99) == "C")
    }

    @Test func unknownRawValueFallsBackToNormal() {
        #expect(MemoryPressure.level(fromRaw: 99) == 0)
    }
}

struct CPUUsageTests {
    @Test func firstSampleHasNoFraction() {
        let current = CPULoad(user: 10, system: 10, nice: 0, idle: 80)
        #expect(CPUUsage.fraction(previous: nil, current: current) == nil)
    }

    @Test func aggregatesAcrossCoreCountsWithoutUInt32Overflow() {
        // 5e9 used ticks cannot fit in UInt32; the old per-core accumulator
        // overflowed here long before the 64-bit counter did.
        let load = CPULoad(user: 4_000_000_000, system: 1_000_000_000, nice: 0, idle: 1_000_000_000)
        #expect(load.used == 5_000_000_000)
        #expect(load.total == 6_000_000_000)
    }

    @Test func computesFractionAcrossLargeCounters() {
        let previous = CPULoad(user: 4_000_000_000, system: 0, nice: 0, idle: 1_000_000_000)
        let current = CPULoad(user: 4_000_000_050, system: 0, nice: 0, idle: 1_000_000_050)
        let fraction = CPUUsage.fraction(previous: previous, current: current)
        #expect(fraction == 0.5)
    }

    @Test func counterRegressionIsNotANegativeRate() {
        let previous = CPULoad(user: 100, system: 0, nice: 0, idle: 100)
        let current = CPULoad(user: 50, system: 0, nice: 0, idle: 50)
        #expect(CPUUsage.fraction(previous: previous, current: current) == nil)
    }
}

struct RateMathTests {
    @Test func bytesPerSecondUsesTheMonotonicInterval() {
        #expect(RateMath.bytesPerSecond(previous: 1_000, current: 2_000, seconds: 2) == 500)
    }

    @Test func counterRegressionIsUnavailable() {
        #expect(RateMath.bytesPerSecond(previous: 2_000, current: 1_000, seconds: 2) == nil)
    }

    @Test func nonPositiveIntervalIsUnavailable() {
        #expect(RateMath.bytesPerSecond(previous: 1_000, current: 2_000, seconds: 0) == nil)
        #expect(RateMath.bytesPerSecond(previous: 1_000, current: 2_000, seconds: -1) == nil)
    }

    @Test func monotonicSeconds() {
        #expect(RateMath.seconds(from: 1_000_000_000, to: 3_000_000_000) == 2)
        #expect(RateMath.seconds(from: 0, to: 1) == nil)
        #expect(RateMath.seconds(from: 3, to: 2) == nil)
    }
}

struct HelperProtocolTests {
    @Test func requestCarriesIDAndCommand() {
        #expect(HelperProtocol.request(id: 7, command: "all") == "7 all\n")
    }

    @Test func parsesVersionedEnvelope() {
        let response = HelperProtocol.parseResponse("7 all 2 12 3622 123 456")
        #expect(response?.id == 7)
        #expect(response?.command == "all")
        #expect(response?.payload == "12 3622 123 456")
    }

    @Test func naFieldsStayUnavailable() {
        let fields = HelperProtocol.fields("12 na 123 456", count: 4)
        #expect(fields?.count == 4)
        #expect(HelperProtocol.double(fields![1]) == nil)
        #expect(HelperProtocol.uint64(fields![2]) == 123)
    }

    @Test func rejectsOldOrMalformedProtocol() {
        #expect(HelperProtocol.parseResponse("gpu 12") == nil)
        #expect(HelperProtocol.parseResponse("7 gpu 1 12") == nil)
        #expect(HelperProtocol.parseResponse("not-an-id gpu 2 12") == nil)
    }

    @Test func lineBufferDrainsEveryCompleteLine() {
        var buffer = LineBuffer()
        buffer.append(Data("7 gpu 2 12\n8 all 2 3 na 4 5\n9 po".utf8))
        #expect(buffer.nextLine() == "7 gpu 2 12")
        #expect(buffer.nextLine() == "8 all 2 3 na 4 5")
        #expect(buffer.nextLine() == nil)
        buffer.append(Data("wer 2 9\n".utf8))
        #expect(buffer.nextLine() == "9 power 2 9")
        #expect(buffer.nextLine() == nil)
    }
}

struct NetworkCountersTests {
    @Test func decodes64BitCountersAboveUInt32() {
        var data = ifmibdata()
        data.ifmd_data.ifi_ibytes = 8_000_000_000
        data.ifmd_data.ifi_obytes = 7_000_000_000
        let parsed = NetworkCounters.from(ifmib: data, interfaceIndex: 42)
        #expect(parsed.interfaceIndex == 42)
        #expect(parsed.receivedBytes == 8_000_000_000)
        #expect(parsed.sentBytes == 7_000_000_000)
    }

    @Test func unknownInterfaceNameIsUnavailable() {
        #expect(NetworkCounters.read(interfaceName: "definitely-not-an-interface") == nil)
    }
}
