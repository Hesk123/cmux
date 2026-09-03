// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import AppKit
import QuartzCore
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT rows 36, 58, 59, 60, 62, 63, 64, 65, 66, 79, 82 and 113.
@MainActor
final class CarouselMotionComponentTests: XCTestCase {

    private func number(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? .nan
    }

    private func animation(_ layer: CALayer, keyPath: String) -> CABasicAnimation? {
        (layer.animationKeys() ?? [])
            .compactMap { layer.animation(forKey: $0) as? CABasicAnimation }
            .first { $0.keyPath == keyPath }
    }

    // MARK: - Chip roll, rows 58, 59, 60, 79

    private func makeChip(reduced: Bool = false) -> (roll: CarouselChipRoll, pill: CALayer, labels: () -> [CALayer]) {
        let pill = CALayer()
        pill.bounds = CGRect(x: 0, y: 0, width: 120, height: 26)
        pill.anchorPoint = CGPoint(x: 0, y: 0.5)
        pill.masksToBounds = true
        var made: [CALayer] = []
        let roll = CarouselChipRoll(
            pill: pill,
            makeLabel: { _ in
                let label = CALayer()
                label.bounds = CGRect(x: 0, y: 0, width: 80, height: 18)
                made.append(label)
                return label
            },
            reduceMotion: .fixed(reduced)
        )
        return (roll, pill, { made })
    }

    func testForwardRollEntersFromTheTopAndBackwardFromTheBottom() {
        // Row 79, the exceeds-source fix for the reference's gap G3.
        let forward = makeChip()
        forward.roll.setInitial("Calendar", pillWidth: 120)
        forward.roll.roll(to: "Notion", pillWidth: 96, direction: .forward)
        let forwardEntry = number(animation(forward.labels()[1], keyPath: "transform.translation.y")?.fromValue)

        let backward = makeChip()
        backward.roll.setInitial("Calendar", pillWidth: 120)
        backward.roll.roll(to: "Notion", pillWidth: 96, direction: .backward)
        let backwardEntry = number(animation(backward.labels()[1], keyPath: "transform.translation.y")?.fromValue)

        XCTAssertGreaterThan(forwardEntry, 0, "forward: the new label starts above the slot")
        XCTAssertLessThan(backwardEntry, 0, "backward: the new label starts below it")
        XCTAssertEqual(forwardEntry, -backwardEntry, accuracy: 0.0001)
    }

    func testOldLabelLeavesByTheOppositeEdge() {
        // Row 58: new in from the top, old out the bottom.
        let chip = makeChip()
        chip.roll.setInitial("Calendar", pillWidth: 120)
        chip.roll.roll(to: "Notion", pillWidth: 96, direction: .forward)
        let entry = number(animation(chip.labels()[1], keyPath: "transform.translation.y")?.fromValue)
        let exit = number(animation(chip.labels()[0], keyPath: "transform.translation.y")?.toValue)
        XCTAssertGreaterThan(entry, 0)
        XCTAssertLessThan(exit, 0)
    }

    func testBothLabelsCrossFade() {
        let chip = makeChip()
        chip.roll.setInitial("Calendar", pillWidth: 120)
        chip.roll.roll(to: "Notion", pillWidth: 96, direction: .forward)
        XCTAssertEqual(number(animation(chip.labels()[1], keyPath: "opacity")?.fromValue), 0, accuracy: 0.0001)
        XCTAssertEqual(number(animation(chip.labels()[1], keyPath: "opacity")?.toValue), 1, accuracy: 0.0001)
        XCTAssertEqual(number(animation(chip.labels()[0], keyPath: "opacity")?.toValue), 0, accuracy: 0.0001)
    }

    func testPillWidthAnimatesWithTheRoll() {
        // Row 60, on two differently sized labels.
        let chip = makeChip()
        chip.roll.setInitial("Calendar", pillWidth: 120)
        chip.roll.roll(to: "Lovable Workspace", pillWidth: 168, direction: .forward)
        guard let widen = animation(chip.pill, keyPath: "bounds.size.width") else {
            return XCTFail("pill width does not animate")
        }
        XCTAssertEqual(number(widen.fromValue), 120, accuracy: 0.5)
        XCTAssertEqual(number(widen.toValue), 168, accuracy: 0.5)
        XCTAssertEqual(widen.duration, CarouselMotion.chipRollDuration, accuracy: 0.0001)
    }

    func testRollIsDelayedSoItSettlesWithTheCard() {
        let chip = makeChip()
        chip.roll.setInitial("Calendar", pillWidth: 120)
        let before = CACurrentMediaTime()
        chip.roll.roll(to: "Notion", pillWidth: 96, direction: .forward)
        guard let entry = animation(chip.labels()[1], keyPath: "transform.translation.y") else {
            return XCTFail("no entry animation")
        }
        XCTAssertEqual(entry.beginTime - before, CarouselMotion.chipRollDelay, accuracy: 0.05)
        // Without .backwards the label would flash at its resting position for
        // the 93 ms before the roll starts.
        XCTAssertEqual(entry.fillMode, .backwards)
    }

    func testReducedMotionRollHasNoTranslationAndNoWidthAnimation() {
        // Row 113.
        let chip = makeChip(reduced: true)
        chip.roll.setInitial("Calendar", pillWidth: 120)
        chip.roll.roll(to: "Lovable Workspace", pillWidth: 168, direction: .forward)
        XCTAssertNil(animation(chip.labels()[1], keyPath: "transform.translation.y"))
        XCTAssertNil(animation(chip.pill, keyPath: "bounds.size.width"))
        XCTAssertNotNil(animation(chip.labels()[1], keyPath: "opacity"), "opacity still interpolates")
        XCTAssertEqual(chip.pill.bounds.width, 168, accuracy: 0.5, "the width still reaches its target")
    }

    // MARK: - Keycap, rows 36, 62, 63

    private func makeKeycap(width: CGFloat = 1344, reduced: Bool = false) -> (hint: CarouselKeycapHint, container: CALayer) {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 300, height: 60)
        let hint = CarouselKeycapHint(
            container: container,
            windowWidth: width,
            makeCap: { _, _, _ in CALayer() },
            reduceMotion: .fixed(reduced)
        )
        return (hint, container)
    }

    func testKeycapIsVisibleImmediatelyWithNoEntranceAnimation() {
        // Row 62: same frame as the chord. emil-design-eng bans animating a
        // keyboard-initiated action outright, so an entrance would be a defect
        // even if it were fast.
        let keycap = makeKeycap()
        keycap.hint.show(.next)
        XCTAssertEqual(keycap.container.opacity, 1)
        XCTAssertNil(keycap.container.animation(forKey: "opacity"))
    }

    func testKeycapRendersThreeCapsForEveryNavigationChord() {
        // Row 36 and rulings D-12/D-15: every chord in this build is three keys.
        for chord in [CarouselKeycapHint.Chord.previous, .next, .grid, .modeToggle] {
            let keycap = makeKeycap()
            keycap.hint.show(chord)
            XCTAssertEqual(chord.caps.count, 3)
            XCTAssertEqual(keycap.container.sublayers?.count, 3)
        }
    }

    func testKeycapGlyphsAreTheKeysActuallyPressed() {
        XCTAssertEqual(CarouselKeycapHint.Chord.previous.caps, ["\u{2303}", "\u{2318}", "\u{2190}"])
        XCTAssertEqual(CarouselKeycapHint.Chord.next.caps, ["\u{2303}", "\u{2318}", "\u{2192}"])
        XCTAssertEqual(CarouselKeycapHint.Chord.grid.caps, ["\u{2303}", "\u{2318}", "M"])
        XCTAssertEqual(CarouselKeycapHint.Chord.modeToggle.caps, ["\u{2303}", "\u{2318}", "K"])
    }

    func testKeycapGroupIsCentredAndSpacedByRow36sRatios() {
        let keycap = makeKeycap()
        keycap.hint.show(.next)
        guard let caps = keycap.container.sublayers, caps.count == 3 else {
            return XCTFail("expected three caps")
        }
        let width = CarouselMotion.keycapWidthRatio * 1344
        let spacing = CarouselMotion.keycapSpacingRatio * 1344
        XCTAssertEqual(caps[0].bounds.width, width, accuracy: 0.001)
        XCTAssertEqual(caps[0].bounds.height, CarouselMotion.keycapHeightRatio * 1344, accuracy: 0.001)
        XCTAssertEqual(caps[1].position.x - caps[0].position.x, width + spacing, accuracy: 0.001)
        XCTAssertEqual(caps[2].position.x - caps[1].position.x, width + spacing, accuracy: 0.001)
        let groupCentre = (caps[0].position.x + caps[2].position.x) / 2
        XCTAssertEqual(groupCentre, keycap.container.bounds.midX, accuracy: 0.001)
    }

    func testKeycapGeometryTracksTheWindowWidth() {
        // The contract's normalization rule: nothing is a fixed pixel count.
        let keycap = makeKeycap(width: 1920)
        keycap.hint.show(.next)
        let cap = keycap.container.sublayers?.first
        XCTAssertEqual(cap?.bounds.width ?? 0, CarouselMotion.keycapWidthRatio * 1920, accuracy: 0.001)
    }

    func testKeycapFadesOutAfterTheDwellWithRow63sProfile() async throws {
        let keycap = makeKeycap()
        keycap.hint.show(.next)
        XCTAssertNil(keycap.container.animation(forKey: "opacity"))
        try await Task.sleep(for: .milliseconds(Int(CarouselMotion.keycapDwell * 1000) + 120))
        XCTAssertEqual(keycap.container.opacity, 0)
    }

    func testRepressBeforeTheDwellExpiresKeepsTheHintUp() async throws {
        let keycap = makeKeycap()
        keycap.hint.show(.next)
        try await Task.sleep(for: .milliseconds(600))
        keycap.hint.show(.previous)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(keycap.container.opacity, 1, "the second press must restart the dwell, not inherit it")
    }

    func testGlyphSwapsWithTheKeyWhileTheHintStaysUp() {
        let keycap = makeKeycap()
        keycap.hint.show(.next)
        keycap.hint.show(.grid)
        XCTAssertEqual(keycap.container.sublayers?.count, 3)
        XCTAssertEqual(keycap.container.opacity, 1)
    }

    // MARK: - Send control, rows 64, 65, 82

    private func makeSend(reduced: Bool = false) -> (
        feedback: CarouselSendFeedback,
        press: CALayer,
        voice: CALayer,
        send: CALayer,
        chips: [CALayer]
    ) {
        let press = CALayer()
        let voice = CALayer()
        let sendIcon = CALayer()
        let chips = [CALayer(), CALayer(), CALayer()]
        let feedback = CarouselSendFeedback(
            pressTarget: press,
            voiceIcon: voice,
            sendIcon: sendIcon,
            suggestionChips: chips,
            reduceMotion: .fixed(reduced)
        )
        return (feedback, press, voice, sendIcon, chips)
    }

    func testVoiceToSendIsAnIconCrossFadeAtRow64sDuration() {
        let subject = makeSend()
        XCTAssertEqual(subject.voice.opacity, 1)
        XCTAssertEqual(subject.send.opacity, 0)
        subject.feedback.setMode(.send)
        XCTAssertEqual(subject.voice.opacity, 0)
        XCTAssertEqual(subject.send.opacity, 1)
        XCTAssertEqual(
            animation(subject.send, keyPath: "opacity")?.duration ?? 0,
            CarouselMotion.voiceSendCrossfade,
            accuracy: 0.0001
        )
    }

    func testSettingTheSameModeTwiceDoesNothing() {
        let subject = makeSend()
        subject.feedback.setMode(.send)
        subject.send.removeAllAnimations()
        subject.feedback.setMode(.send)
        XCTAssertNil(animation(subject.send, keyPath: "opacity"))
    }

    func testPressFeedbackDipsBelowOneAndReturns() {
        // Row 82, the exceeds-source improvement.
        let subject = makeSend()
        subject.feedback.flashPress()
        guard let group = subject.press.animation(forKey: "press") as? CAAnimationGroup,
              let steps = group.animations as? [CABasicAnimation], steps.count == 2 else {
            return XCTFail("no press group")
        }
        XCTAssertEqual(number(steps[0].toValue), Double(CarouselMotion.sendPressScale), accuracy: 0.0001)
        XCTAssertLessThan(number(steps[0].toValue), 1.0)
        XCTAssertEqual(number(steps[1].toValue), 1.0, accuracy: 0.0001)
        XCTAssertEqual(steps[0].duration, CarouselMotion.sendPressIn, accuracy: 0.0001)
        XCTAssertEqual(steps[1].beginTime, CarouselMotion.sendPressIn, accuracy: 0.0001)
    }

    func testPressFeedbackReachesFullDepthInsideTwoFrames() {
        // Row 82 asserts the dip within 2 frames of Return; the ease-out's
        // first two frames must already be visibly below 1.0.
        XCTAssertLessThanOrEqual(CarouselMotion.sendPressIn, 2.0 * 0.0833)
    }

    func testSendDimsTheChipsAndClearsTheInputOneFrameLater() async throws {
        // Row 65's U2 half.
        let subject = makeSend()
        var cleared = false
        subject.feedback.didSend { cleared = true }
        for chip in subject.chips {
            XCTAssertEqual(chip.opacity, 0.4, accuracy: 0.0001)
            XCTAssertEqual(
                animation(chip, keyPath: "opacity")?.duration ?? 0,
                CarouselMotion.sendEffectsDuration,
                accuracy: 0.0001
            )
        }
        XCTAssertFalse(cleared, "the input must not clear on the send frame itself")
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertTrue(cleared)
    }

    func testChipsComeBackWhenGenerationFinishes() {
        let subject = makeSend()
        subject.feedback.didSend {}
        subject.feedback.didFinishGenerating()
        for chip in subject.chips {
            XCTAssertEqual(chip.opacity, 1.0, accuracy: 0.0001)
        }
    }

    func testReducedMotionSuppressesOnlyThePressScale() {
        // Row 113 removes scale, and keeps the opacity changes that carry
        // meaning: the chips still dim so "generating" is still legible.
        let subject = makeSend(reduced: true)
        subject.feedback.didSend {}
        XCTAssertNil(subject.press.animation(forKey: "press"))
        XCTAssertEqual(subject.chips[0].opacity, 0.4, accuracy: 0.0001)
    }

    func testAccessibilityFloorStrings() {
        // Contract rows 108-113 annotation: every new status element ships
        // label, role and value, owned here and published by U1's card.
        XCTAssertEqual(CarouselKeycapHint.accessibilityLabel, "Carousel keyboard shortcuts")
        XCTAssertEqual(CarouselKeycapHint.Chord.previous.accessibilityValue, "Control Command Left Arrow")
        XCTAssertEqual(CarouselKeycapHint.Chord.next.accessibilityValue, "Control Command Right Arrow")
        XCTAssertEqual(CarouselKeycapHint.Chord.grid.accessibilityValue, "Control Command M")
        XCTAssertEqual(CarouselKeycapHint.Chord.modeToggle.accessibilityValue, "Control Command K")

        XCTAssertEqual(CarouselWorkingIndicator.accessibilityLabel, "Agent activity")
        let dots = makeDots()
        XCTAssertEqual(dots.indicator.accessibilityValue, "idle")
        dots.indicator.setRunning(true)
        XCTAssertEqual(dots.indicator.accessibilityValue, "working")
        dots.indicator.setRunning(false)
        XCTAssertEqual(dots.indicator.accessibilityValue, "idle")

        // The chip publishes the settled text, never a mid-roll frame: the
        // value is already the incoming label while the pixels travel.
        let chip = makeChip()
        chip.roll.setInitial("Calendar", pillWidth: 120)
        XCTAssertEqual(chip.roll.currentText, "Calendar")
        chip.roll.roll(to: "Notion", pillWidth: 96, direction: .forward)
        XCTAssertEqual(chip.roll.currentText, "Notion")
    }

    // MARK: - Working indicator, row 66

    private func makeDots(reduced: Bool = false) -> (indicator: CarouselWorkingIndicator, dots: [CALayer]) {
        let dots = [CALayer(), CALayer(), CALayer()]
        return (CarouselWorkingIndicator(dots: dots, reduceMotion: .fixed(reduced)), dots)
    }

    func testDotsPulseStaggeredByRow66sPhase() {
        let subject = makeDots()
        subject.indicator.setRunning(true)
        let pulses = subject.dots.compactMap {
            $0.animation(forKey: "carousel.workingPulse") as? CAKeyframeAnimation
        }
        XCTAssertEqual(pulses.count, 3)
        XCTAssertEqual(
            pulses[1].beginTime - pulses[0].beginTime,
            CarouselMotion.workingDotPhase,
            accuracy: 0.0001,
            "row 66: dot 2 peaks 220 ms after dot 1"
        )
        XCTAssertEqual(
            pulses[2].beginTime - pulses[1].beginTime,
            CarouselMotion.workingDotPhase,
            accuracy: 0.0001
        )
    }

    func testDotLoopPeriodCoversTheWholeCascade() {
        let subject = makeDots()
        subject.indicator.setRunning(true)
        let pulse = subject.dots[0].animation(forKey: "carousel.workingPulse")
        XCTAssertEqual(
            pulse?.duration ?? 0,
            CarouselMotion.workingDotPhase * Double(CarouselMotion.workingDotCount),
            accuracy: 0.0001
        )
        XCTAssertEqual(pulse?.repeatCount ?? 0, .greatestFiniteMagnitude)
    }

    func testStoppingClearsTheLoop() {
        let subject = makeDots()
        subject.indicator.setRunning(true)
        subject.indicator.setRunning(false)
        XCTAssertTrue(subject.dots.allSatisfy { $0.animation(forKey: "carousel.workingPulse") == nil })
        XCTAssertTrue(subject.dots.allSatisfy { $0.opacity == 0 })
    }

    func testGoingOffScreenPausesTheLoopWithoutClearingTheRunningState() {
        // Up to six cards can be running; a repeating animation on a hidden
        // layer still costs a commit every frame.
        let subject = makeDots()
        subject.indicator.setRunning(true)
        subject.indicator.setVisible(false)
        XCTAssertTrue(subject.dots.allSatisfy { $0.animation(forKey: "carousel.workingPulse") == nil })
        XCTAssertTrue(subject.indicator.isRunning)
        subject.indicator.setVisible(true)
        XCTAssertTrue(subject.dots.allSatisfy { $0.animation(forKey: "carousel.workingPulse") != nil })
    }

    func testReducedMotionHoldsTheDotsLitInsteadOfPulsing() {
        // Row 113. A blank status pill would remove information, which is not
        // what reduced motion asks for.
        let subject = makeDots(reduced: true)
        subject.indicator.setRunning(true)
        XCTAssertTrue(subject.dots.allSatisfy { $0.animation(forKey: "carousel.workingPulse") == nil })
        XCTAssertTrue(subject.dots.allSatisfy { $0.opacity == 1 })
    }
}
