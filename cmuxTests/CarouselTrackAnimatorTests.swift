// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import AppKit
import QuartzCore
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT rows 52, 53, 54, 55, 56, 113, 115 and ruling D-14.
@MainActor
final class CarouselTrackAnimatorTests: XCTestCase {

    private let viewport = CGRect(x: 0, y: 0, width: 1344, height: 1080)
    private let pitch: CGFloat = 993.96

    private func makeSubject(reduced: Bool = false) -> (
        animator: CarouselTrackAnimator,
        layers: CarouselTrackAnimator.Layers,
        cards: [CALayer],
        host: NSView
    ) {
        let layers = CarouselTrackAnimator.makeLayers(viewport: viewport)
        let animator = CarouselTrackAnimator(
            layers: layers,
            pitch: pitch,
            reduceMotion: .fixed(reduced)
        )
        // Five slots, centre at index 2: the two neighbours ramp and the two
        // outer cards hold, which is row 54's stated solvability observable.
        let host = NSView(frame: viewport)
        host.wantsLayer = true
        host.layer?.addSublayer(layers.recoil)
        let cards = (0..<5).map { slot -> CALayer in
            let card = CALayer()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.bounds = CGRect(x: 0, y: 0, width: 968, height: 761)
            card.position = CGPoint(x: viewport.midX + CGFloat(slot - 2) * pitch, y: viewport.midY)
            layers.track.addSublayer(card)
            CATransaction.commit()
            animator.register(
                card: card,
                scale: slot == 2 ? CarouselMotion.centreScale : CarouselMotion.flankScale
            )
            return card
        }
        return (animator, layers, cards, host)
    }

    private func modelValue(_ layer: CALayer, _ keyPath: String) -> CGFloat {
        guard let number = layer.value(forKeyPath: keyPath) as? NSNumber else { return .nan }
        return CGFloat(number.doubleValue)
    }

    private func animations(_ layer: CALayer, keyPath: String) -> [CAPropertyAnimation] {
        (layer.animationKeys() ?? []).compactMap { layer.animation(forKey: $0) as? CAPropertyAnimation }
            .filter { $0.keyPath == keyPath }
    }

    // MARK: - Row 52

    func testForwardSwitchTargetsExactlyOnePitch() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        XCTAssertEqual(modelValue(subject.layers.track, "transform.translation.x"), -pitch, accuracy: 0.0001)
    }

    func testBackwardSwitchMirrorsTheDirection() {
        let subject = makeSubject()
        subject.animator.advance(by: -1, ramps: .init()) {}
        XCTAssertEqual(modelValue(subject.layers.track, "transform.translation.x"), pitch, accuracy: 0.0001)
    }

    func testTranslateUsesRow52sDurationAndTheFittedCurve() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        let moves = animations(subject.layers.track, keyPath: "transform.translation.x")
        XCTAssertEqual(moves.count, 1)
        let move = try? XCTUnwrap(moves.first)
        XCTAssertEqual(move?.duration ?? 0, CarouselMotion.switchDuration, accuracy: 0.0001)
        XCTAssertEqual(move?.timingFunction, CarouselMotion.switchCurve)
    }

    func testTranslateIsAdditiveAndCarriesTheWholeDelta() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        guard let move = animations(subject.layers.track, keyPath: "transform.translation.x").first as? CABasicAnimation else {
            return XCTFail("no translate animation")
        }
        XCTAssertTrue(move.isAdditive)
        XCTAssertEqual((move.fromValue as? NSNumber)?.doubleValue ?? 0, Double(pitch), accuracy: 0.0001)
        XCTAssertEqual((move.toValue as? NSNumber)?.doubleValue ?? .nan, 0, accuracy: 0.0001)
    }

    // MARK: - Row 55 and D-14

    func testEnteringAndLeavingCardsRampAndEveryOtherCardHolds() {
        let subject = makeSubject()
        subject.animator.advance(
            by: 1,
            ramps: .init(entering: subject.cards[3], leaving: subject.cards[2])
        ) {}

        XCTAssertEqual(modelValue(subject.cards[3], "transform.scale"), CarouselMotion.centreScale, accuracy: 0.0001)
        XCTAssertEqual(modelValue(subject.cards[2], "transform.scale"), CarouselMotion.flankScale, accuracy: 0.0001)

        // The observable row 54 says the harness solves T = r_hold / 0.94 from.
        for index in [0, 1, 4] {
            XCTAssertEqual(
                modelValue(subject.cards[index], "transform.scale"),
                CarouselMotion.flankScale,
                accuracy: 0.0001,
                "card \(index) must hold 0.94 through the switch"
            )
            XCTAssertTrue(
                animations(subject.cards[index], keyPath: "transform.scale").isEmpty,
                "card \(index) must carry no scale animation at all"
            )
        }
    }

    func testCardRampsAreAdditiveInBothDirections() {
        let subject = makeSubject()
        subject.animator.advance(
            by: 1,
            ramps: .init(entering: subject.cards[3], leaving: subject.cards[2])
        ) {}
        let up = animations(subject.cards[3], keyPath: "transform.scale").first as? CABasicAnimation
        let down = animations(subject.cards[2], keyPath: "transform.scale").first as? CABasicAnimation
        XCTAssertEqual(up?.isAdditive, true)
        XCTAssertEqual(down?.isAdditive, true)
        // entering: 0.94 - 1.00 = -0.06 decaying to zero on top of a 1.00 model.
        XCTAssertEqual((up?.fromValue as? NSNumber)?.doubleValue ?? .nan, -0.06, accuracy: 0.0001)
        // leaving: 1.00 - 0.94 = +0.06 on top of a 0.94 model.
        XCTAssertEqual((down?.fromValue as? NSNumber)?.doubleValue ?? .nan, 0.06, accuracy: 0.0001)
    }

    func testCardScaleNeverAnimatesTheTrack() {
        // D-14's composition rule: the per-card ramp must not touch the layer
        // that carries the recoil, or every card would share the ramp too.
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init(entering: subject.cards[3], leaving: subject.cards[2])) {}
        XCTAssertTrue(animations(subject.layers.track, keyPath: "transform.scale").isEmpty)
    }

    // MARK: - Row 54

    func testRecoilIsOneKeyframeOnTheRecoilLayerWithRow54sShape() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        guard let dip = subject.layers.recoil.animation(forKey: "carousel.recoil") as? CAKeyframeAnimation else {
            return XCTFail("no recoil keyframe")
        }
        XCTAssertEqual(dip.keyPath, "transform.scale")
        XCTAssertEqual(dip.duration, CarouselMotion.switchDuration, accuracy: 0.0001)
        XCTAssertEqual(dip.values?.count, 5)
        let values = (dip.values ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
        XCTAssertEqual(values.first ?? .nan, 1.0, accuracy: 0.0001)
        XCTAssertEqual(values[2], Double(CarouselMotion.recoilTrough), accuracy: 0.0001)
        XCTAssertEqual(values.last ?? .nan, 1.0, accuracy: 0.0001)
        let keyTimes = (dip.keyTimes ?? []).map(\.doubleValue)
        XCTAssertEqual(keyTimes[2], Double(CarouselMotion.recoilTroughFraction), accuracy: 0.0001)
    }

    func testRecoilIsReplacedNotAccumulated() {
        // Two additive dips would sum to about 0.942, outside row 54's
        // 0.971 +/- 0.008. Interruption keeps exactly one.
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        subject.animator.advance(by: 1, ramps: .init()) {}
        XCTAssertEqual(subject.layers.recoil.animationKeys()?.count, 1)
    }

    func testRecoilLayerScalesAboutTheViewportCentre() {
        let layers = CarouselTrackAnimator.makeLayers(viewport: viewport)
        XCTAssertEqual(layers.recoil.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(layers.recoil.position, CGPoint(x: viewport.midX, y: viewport.midY))
        XCTAssertTrue(layers.track.superlayer === layers.recoil)
    }

    // MARK: - Row 56

    func testRapidPressesRetargetAndAccumulateRatherThanQueue() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        subject.animator.advance(by: 1, ramps: .init()) {}
        XCTAssertEqual(
            modelValue(subject.layers.track, "transform.translation.x"),
            -2 * pitch,
            accuracy: 0.0001,
            "two presses land exactly two pitches, never 1.9 or 2.1"
        )
        XCTAssertEqual(
            animations(subject.layers.track, keyPath: "transform.translation.x").count,
            2,
            "the second press must add a decaying delta, not replace the first"
        )
    }

    func testSecondPressCarriesOnlyTheNewDelta() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        subject.animator.advance(by: 1, ramps: .init()) {}
        let moves = animations(subject.layers.track, keyPath: "transform.translation.x")
            .compactMap { $0 as? CABasicAnimation }
        // Composite at the interrupt = newTarget + sum(deltas) = the value
        // already on screen. Each delta is exactly one pitch.
        for move in moves {
            XCTAssertEqual((move.fromValue as? NSNumber)?.doubleValue ?? .nan, Double(pitch), accuracy: 0.0001)
        }
    }

    func testReversalReturnsToTheStartingSlot() {
        let subject = makeSubject()
        subject.animator.advance(by: 1, ramps: .init()) {}
        subject.animator.advance(by: -1, ramps: .init()) {}
        XCTAssertEqual(modelValue(subject.layers.track, "transform.translation.x"), 0, accuracy: 0.0001)
    }

    func testFivePressBurstLandsExactlyFivePitches() {
        let subject = makeSubject()
        for _ in 0..<5 { subject.animator.advance(by: 1, ramps: .init()) {} }
        XCTAssertEqual(
            modelValue(subject.layers.track, "transform.translation.x"),
            -5 * pitch,
            accuracy: 0.0001
        )
    }

    func testZeroSlotAdvanceIsANoOpThatStillSettles() {
        let subject = makeSubject()
        var settled = false
        subject.animator.advance(by: 0, ramps: .init()) { settled = true }
        XCTAssertTrue(settled)
        XCTAssertTrue(animations(subject.layers.track, keyPath: "transform.translation.x").isEmpty)
        XCTAssertNil(subject.layers.recoil.animation(forKey: "carousel.recoil"))
    }

    // MARK: - Row 113

    func testReducedMotionCrossFadesWithNoTransformAnimation() {
        let subject = makeSubject(reduced: true)
        subject.animator.advance(
            by: 1,
            ramps: .init(entering: subject.cards[3], leaving: subject.cards[2])
        ) {}

        let fade = CarouselTrackAnimator.makeReducedMotionFade()
        XCTAssertEqual(fade.type, .fade)
        XCTAssertEqual(fade.duration, CarouselMotion.reducedMotionCrossfade)
        XCTAssertTrue(animations(subject.layers.track, keyPath: "transform.translation.x").isEmpty)
        XCTAssertTrue(animations(subject.layers.recoil, keyPath: "transform.scale").isEmpty)
        XCTAssertTrue(animations(subject.cards[3], keyPath: "transform.scale").isEmpty)
        XCTAssertTrue(animations(subject.cards[2], keyPath: "transform.scale").isEmpty)
    }

    func testReducedMotionStillReachesTheSettledState() {
        let subject = makeSubject(reduced: true)
        subject.animator.advance(
            by: 1,
            ramps: .init(entering: subject.cards[3], leaving: subject.cards[2])
        ) {}
        XCTAssertEqual(modelValue(subject.layers.track, "transform.translation.x"), -pitch, accuracy: 0.0001)
        // Row 113's stated end state: the flanks keep their 0.94 delta.
        XCTAssertEqual(modelValue(subject.cards[3], "transform.scale"), 1.0, accuracy: 0.0001)
        XCTAssertEqual(modelValue(subject.cards[2], "transform.scale"), 0.94, accuracy: 0.0001)
        XCTAssertEqual(modelValue(subject.cards[0], "transform.scale"), 0.94, accuracy: 0.0001)
    }

    func testReducedMotionCrossFadeUsesTheShorterDuration() {
        let subject = makeSubject(reduced: true)
        subject.animator.advance(by: 1, ramps: .init()) {}
        XCTAssertEqual(CarouselTrackAnimator.makeReducedMotionFade().duration, CarouselMotion.reducedMotionCrossfade, accuracy: 0.0001)
    }

    // MARK: - Row 115

    func testSettleFiresOnceAfterTheSwitchDuration() async throws {
        let subject = makeSubject()
        var settleCount = 0
        subject.animator.advance(by: 1, ramps: .init()) { settleCount += 1 }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(settleCount, 1)
    }

    func testASupersededSwitchNeverFiresItsSettle() async throws {
        // Row 115 mounts the live centre from the settle callback. A stale
        // callback would mount the wrong session's terminal.
        let subject = makeSubject()
        var first = 0
        var second = 0
        subject.animator.advance(by: 1, ramps: .init()) { first += 1 }
        subject.animator.advance(by: 1, ramps: .init()) { second += 1 }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(first, 0, "the replaced switch must not remount anything")
        XCTAssertEqual(second, 1)
    }
}
