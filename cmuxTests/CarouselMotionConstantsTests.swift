import QuartzCore
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT rows 52, 54, 55, 59, 63, 64, 66, 82, 113, 115 — the constants, and
/// the arithmetic the contract derives them from.
@MainActor
final class CarouselMotionConstantsTests: XCTestCase {

    func testSwitchCurveIsTheCurveMeasuredFromTheSource() {
        // The fit in CarouselMotion's doc comment says easeOutCubic. Assert the
        // control points rather than the prose, so a later "let's try a
        // punchier curve" edit fails here instead of silently in a video.
        var points = [Float](repeating: 0, count: 2)
        let curve = CarouselMotion.switchCurve
        curve.getControlPoint(at: 1, values: &points)
        XCTAssertEqual(points[0], 0.215, accuracy: 0.0005)
        XCTAssertEqual(points[1], 0.61, accuracy: 0.0005)
        curve.getControlPoint(at: 2, values: &points)
        XCTAssertEqual(points[0], 0.355, accuracy: 0.0005)
        XCTAssertEqual(points[1], 1.0, accuracy: 0.0005)
    }

    func testSwitchCurveNeverOvershoots() {
        // Row 53. A cubic bezier with both y control points in [0, 1] cannot
        // exceed 1, so no-overshoot is a property of the curve rather than
        // something the harness has to catch after the fact.
        var points = [Float](repeating: 0, count: 2)
        for index in 1...2 {
            CarouselMotion.switchCurve.getControlPoint(at: index, values: &points)
            XCTAssertGreaterThanOrEqual(points[1], 0)
            XCTAssertLessThanOrEqual(points[1], 1)
        }
    }

    func testChipRollSettlesWithTheCardTranslate() {
        // Row 59's second clause: settle within 2 frames of the card's.
        let chipSettle = CarouselMotion.chipRollDelay + CarouselMotion.chipRollDuration
        XCTAssertEqual(chipSettle, CarouselMotion.switchDuration, accuracy: 0.001)
        XCTAssertEqual(CarouselMotion.chipRollDelay, 0.093, accuracy: 0.001)
    }

    func testChipRollDurationIsInsideRow59Tolerance() {
        XCTAssertEqual(CarouselMotion.chipRollDuration, 0.207, accuracy: 0.030)
    }

    func testRecoilTroughLandsAtThirtyPercentOfTheTranslate() {
        // Row 54: trough at 30 % +/- 10 % of the translate, depth 0.971 +/- 0.008.
        XCTAssertEqual(CarouselMotion.recoilTroughFraction, 0.30, accuracy: 0.10)
        XCTAssertEqual(CarouselMotion.recoilTrough, 0.971, accuracy: 0.008)
    }

    func testRecoilPhasesMatchTheSourcesSixtyFiveAndOneEightyFive() {
        let total = CarouselMotion.switchDuration
        let descent = (CarouselMotion.recoilTroughFraction - CarouselMotion.recoilHoldInFraction) * CGFloat(total)
        let ascent = (CarouselMotion.recoilReturnFraction - CarouselMotion.recoilTroughFraction) * CGFloat(total)
        XCTAssertEqual(Double(descent), 0.065, accuracy: 0.002)
        XCTAssertEqual(Double(ascent), 0.185, accuracy: 0.002)
    }

    func testRecoilKeyTimesAreOrdered() {
        XCTAssertLessThan(CarouselMotion.recoilHoldInFraction, CarouselMotion.recoilTroughFraction)
        XCTAssertLessThan(CarouselMotion.recoilTroughFraction, CarouselMotion.recoilReturnFraction)
        XCTAssertLessThan(CarouselMotion.recoilReturnFraction, 1.0)
    }

    func testDurationsInsideTheirContractTolerances() {
        XCTAssertEqual(CarouselMotion.switchDuration, 0.300, accuracy: 0.045)     // row 52
        XCTAssertEqual(CarouselMotion.keycapFadeOut, 0.083, accuracy: 0.025)      // row 63
        XCTAssertEqual(CarouselMotion.voiceSendCrossfade, 0.120, accuracy: 0.020) // row 64
        XCTAssertEqual(CarouselMotion.sendEffectsDuration, 0.165, accuracy: 0.025) // row 65
        XCTAssertEqual(Double(CarouselMotion.workingDotPhase), 0.220, accuracy: 0.060) // row 66
    }

    func testKeycapDwellInsideTheRow63Window() {
        XCTAssertGreaterThanOrEqual(CarouselMotion.keycapDwell, 1.1)
        XCTAssertLessThanOrEqual(CarouselMotion.keycapDwell, 1.9)
    }

    func testReducedMotionSettlesInsideRow52Budget() {
        // Row 113: "row 52's settle budget still applies".
        XCTAssertLessThanOrEqual(
            CarouselMotion.reducedMotionCrossfade,
            CarouselMotion.switchDuration + 0.045
        )
    }

    func testKeycapGeometryIsRow36sRatios() {
        let width = 1344.0
        XCTAssertEqual(CarouselMotion.keycapWidthRatio * width, 40, accuracy: 0.5)
        XCTAssertEqual(CarouselMotion.keycapHeightRatio * width, 38, accuracy: 0.5)
        XCTAssertEqual(CarouselMotion.keycapRadiusRatio * width, 11, accuracy: 0.5)
        XCTAssertEqual(CarouselMotion.keycapSpacingRatio * width, 6.5, accuracy: 0.5)
    }

    func testReduceMotionGateIsInjectable() {
        XCTAssertTrue(CarouselReduceMotion.fixed(true).isEnabled)
        XCTAssertFalse(CarouselReduceMotion.fixed(false).isEnabled)
    }
}
