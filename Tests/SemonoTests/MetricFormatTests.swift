import Testing
@testable import Semono

struct MetricFormatTests {
    @Test func hudSwapPadsToFour() {
        #expect(MetricFormat.swap(0) == "  0B")
        #expect(MetricFormat.swap(999) == "999B")
        #expect(MetricFormat.swap(1_000) == "  1K")
        #expect(MetricFormat.swap(2_000_000) == "  2M")
    }

    @Test func hudSpeedPadsToFive() {
        #expect(MetricFormat.speed(-1) == "   0B")
        #expect(MetricFormat.speed(999) == " 999B")
        #expect(MetricFormat.speed(12_000) == "  12K")
    }
}

struct ColorScaleTests {
    @Test func normalizedRSSIBounds() {
        #expect(ColorScale.normalizedRSSI(0) == 0)
        #expect(ColorScale.normalizedRSSI(-30) == 0)
        #expect(ColorScale.normalizedRSSI(-60) == 0.5)
        #expect(ColorScale.normalizedRSSI(-90) == 1.0)
        #expect(ColorScale.normalizedRSSI(-100) == 1.0)
    }
}
