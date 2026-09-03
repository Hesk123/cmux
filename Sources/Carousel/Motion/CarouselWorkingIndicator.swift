import AppKit
import QuartzCore

/// The agent-working indicator: row 66's three-dot staggered pulse.
///
/// # Why this is a live overlay and not part of the card
///
/// Row 66 requires the indicator to be correct on a **non-centred** card, and
/// D-2 makes every non-centred card a `CALayer` snapshot refreshed at 4 Hz. A
/// pulse baked into those pixels would sample the animation four times a second
/// and read as a stutter, not a pulse. So the dots are their own layers,
/// composited *above* the snapshot in the card's status pill, and they animate
/// on the compositor whether their card is live or a still image.
///
/// This is also why the animation is declarative rather than tick-driven:
/// `emil-design-eng`'s note that CSS animations keep running when the main
/// thread is busy is the same property Core Animation gives here. A looping
/// pulse driven from a timer would stall exactly when the terminal is busy,
/// which is precisely when the indicator is on screen.
@MainActor
final class CarouselWorkingIndicator {

    private static let pulseKey = "carousel.workingPulse"

    private let dots: [CALayer]
    private let reduceMotion: CarouselReduceMotion

    private(set) var isRunning = false

    /// Accessibility floor (contract rows 108-113 annotation): VoiceOver label
    /// and value, published by U1's card element. The dots are raw CALayers
    /// and carry no accessibility information themselves.
    static let accessibilityLabel = "Agent activity"
    var accessibilityValue: String { isRunning ? "working" : "idle" }

    /// One full loop. Three dots at row 66's 220 ms phase means the cascade
    /// repeats every 660 ms — 1.5 Hz, comfortably clear of the slow-oscillation
    /// band `apple-design` warns about for looping motion.
    private var period: CFTimeInterval {
        CarouselMotion.workingDotPhase * CFTimeInterval(CarouselMotion.workingDotCount)
    }

    init(dots: [CALayer], reduceMotion: CarouselReduceMotion) {
        self.dots = dots
        self.reduceMotion = reduceMotion
    }

    /// - Parameter running: row 127's agent-running signal for this card.
    func setRunning(_ running: Bool) {
        guard running != isRunning else { return }
        isRunning = running
        if running { start() } else { stop() }
    }

    /// Stops the loop while the card is off screen. A repeating animation on an
    /// invisible layer still costs a commit per frame, and there are up to six
    /// cards. U1 calls this from its visibility bookkeeping.
    func setVisible(_ visible: Bool) {
        guard isRunning else { return }
        if visible { start() } else { removeAnimations() }
    }

    private func start() {
        removeAnimations()

        // Row 113 keeps a reduced-motion state legible rather than blank: the
        // dots hold at their lit value instead of pulsing, so "an agent is
        // working" is still readable with no motion at all.
        guard !reduceMotion.isEnabled else {
            carouselCommit { self.dots.forEach { $0.opacity = 1 } }
            return
        }

        let now = CACurrentMediaTime()
        for (index, dot) in dots.enumerated() {
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            // One dot lit, the other two low, then back — a cascade rather than
            // three synchronised blinks. Values match the source's measured
            // brightness swing (dot 1 ran 47 -> 57 -> 43 of 255) rather than a
            // full 0-to-1 flash, which reads as a strobe at this size.
            pulse.values = [0.35, 1.0, 0.35, 0.35]
            pulse.keyTimes = [0, 0.167, 0.333, 1]
            pulse.timingFunctions = [
                CarouselMotion.switchCurve,
                CarouselMotion.switchCurve,
                CarouselMotion.linearCurve,
            ]
            pulse.duration = period
            pulse.repeatCount = .greatestFiniteMagnitude
            pulse.beginTime = now + CarouselMotion.workingDotPhase * CFTimeInterval(index)
            pulse.fillMode = .backwards
            carouselCommit { dot.add(pulse, forKey: Self.pulseKey) }
        }
    }

    private func stop() {
        removeAnimations()
        carouselCommit { self.dots.forEach { $0.opacity = 0 } }
    }

    private func removeAnimations() {
        dots.forEach { $0.removeAnimation(forKey: Self.pulseKey) }
    }
}
