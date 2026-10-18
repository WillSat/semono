import CoreGraphics
import Testing
@testable import Semono

@MainActor
struct HUDPositionTests {
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 700)
    private let topEdge: CGFloat = 660
    private let size = CGSize(width: 140, height: 24)

    @Test func defaultCornerAndMargins() {
        #expect(HUDPosition(rawValue: SettingsStore.Defaults.hudCorner) == .bottomLeft)
        #expect(SettingsStore.Defaults.hudMarginHorizontal == 0)
        #expect(SettingsStore.Defaults.hudMarginVertical == 0)
    }

    @Test func fourCornersWithZeroMargins() {
        let topLeft = HUDPosition.topLeft.frame(
            for: size, screenFrame: screen, topEdge: topEdge
        )
        #expect(topLeft.minX == 0)
        #expect(topLeft.maxY == topEdge)

        let topRight = HUDPosition.topRight.frame(
            for: size, screenFrame: screen, topEdge: topEdge
        )
        #expect(topRight.maxX == screen.maxX)
        #expect(topRight.maxY == topEdge)

        let bottomLeft = HUDPosition.bottomLeft.frame(
            for: size, screenFrame: screen, topEdge: topEdge
        )
        #expect(bottomLeft.minX == 0)
        #expect(bottomLeft.minY == screen.minY)

        let bottomRight = HUDPosition.bottomRight.frame(
            for: size, screenFrame: screen, topEdge: topEdge
        )
        #expect(bottomRight.maxX == screen.maxX)
        #expect(bottomRight.minY == screen.minY)
    }

    @Test func marginsAreAppliedOnTheAnchoredSides() {
        let horizontal: CGFloat = 12
        let vertical: CGFloat = 10

        let bottomLeft = HUDPosition.bottomLeft.frame(
            for: size,
            screenFrame: screen,
            topEdge: topEdge,
            horizontalMargin: horizontal,
            verticalMargin: vertical
        )
        #expect(bottomLeft.minX == 12)
        #expect(bottomLeft.minY == 10)

        let bottomRight = HUDPosition.bottomRight.frame(
            for: size,
            screenFrame: screen,
            topEdge: topEdge,
            horizontalMargin: horizontal,
            verticalMargin: vertical
        )
        #expect(bottomRight.maxX == screen.maxX - horizontal)
        #expect(bottomRight.minY == 10)

        let topRight = HUDPosition.topRight.frame(
            for: size,
            screenFrame: screen,
            topEdge: topEdge,
            horizontalMargin: horizontal,
            verticalMargin: vertical
        )
        #expect(topRight.maxX == screen.maxX - horizontal)
        #expect(topRight.maxY == topEdge - vertical)
    }

    @Test func rightCornersAreAnchoredByTheirRightEdge() {
        let wider = CGSize(width: 300, height: 24)
        let right = HUDPosition.bottomRight.frame(
            for: wider,
            screenFrame: screen,
            topEdge: topEdge,
            horizontalMargin: 12
        )
        #expect(right.maxX == screen.maxX - 12)
        #expect(right.minX == screen.maxX - 12 - wider.width)
    }

    @Test func oversizedHUDStaysReachable() {
        let huge = CGSize(width: 2000, height: 2000)
        let frame = HUDPosition.topRight.frame(
            for: huge, screenFrame: screen, topEdge: topEdge
        )
        #expect(frame.minX == 0)
        #expect(frame.minY == 0)
    }
}
