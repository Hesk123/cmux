import AppKit
import QuartzCore

/// Every duration, curve and motion constant the carousel's motion layer uses.
///
/// CONTRACT rows 52-68, 79, 82, 112-115 and D-14. This is the only place a
/// motion constant exists; `CarouselTrackAnimator`, `CarouselChipRoll`,
/// `CarouselKeycapHint`, `CarouselSendFeedback` and
/// `CarouselWorkingIndicator` all read from here so a spec change is one edit.
///
/// Geometry (pitch, card size, gap) is NOT here — it is U1's `CarouselMetrics`.
/// This unit takes the pitch as a parameter so the motion layer carries no
/// second copy of a layout constant.
@MainActor
enum CarouselMotion {

    // MARK: - Curves

    /// The switch curve, row 52's "ease-out".
    ///
    /// This is `easeOutCubic`, and it is measured rather than chosen. Fitting
    /// VIDEO-REVIEW §2.1's own seq1 edge table (samples 0.400-0.533 s,
    /// normalised against the 309 ms switch and the 878 CSS pitch) against five
    /// candidate curves gives, as RMS error in normalised progress:
    ///
    ///     easeOutCubic  0.0102   <- this one
    ///     easeOutQuart  0.0294
    ///     easeOutQuint  0.0610
    ///     easeOutQuad   0.0699
    ///     kCAMediaTimingFunctionEaseOut  0.1274
    ///
    /// Two consequences worth stating. The source's curve is cubic to within
    /// 1 % of progress at every sample, so this is a reproduction and not a
    /// taste call. And Core Animation's built-in `.easeOut` is twelve times
    /// worse — which is the concrete, local form of the `emil-design-eng` rule
    /// that the platform's built-in easings are too weak to use for UI.
    ///
    /// Control points are the standard cubic-bezier form of `1-(1-t)^3`.
    static let switchCurve = CAMediaTimingFunction(controlPoints: 0.215, 0.61, 0.355, 1)

    /// The recoil's descending half only (row 54: "~65 ms in (ease-in)").
    ///
    /// `emil-design-eng` bans ease-in for UI because it delays the first frame
    /// the user is watching. That ban is about an element *entering or
    /// exiting*, where the delay reads as latency. This curve is neither: it is
    /// the middle of a motion that is already running, where the track takes up
    /// slack before springing back, and the source measured it as ease-in. The
    /// exception is deliberate and is confined to this one 65 ms segment.
    static let recoilInCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)

    static let linearCurve = CAMediaTimingFunction(name: .linear)

    // MARK: - Durations, seconds

    /// Row 52. Settle is asserted at 300 ms ± 45 ms.
    static let switchDuration: CFTimeInterval = 0.300

    /// Row 59: 207 ms ± 30 ms.
    static let chipRollDuration: CFTimeInterval = 0.207

    /// Row 59 also requires the chip to settle within 2 frames of the card.
    /// The source's prose says the roll "runs one frame or two behind the card
    /// translation, so the chip settles at roughly the same moment" — at a
    /// 207 ms roll those two statements cannot both hold, because a roll
    /// starting 2 frames in settles 60 ms early. Co-settlement is the
    /// observable the contract asserts mechanically, so the roll is delayed by
    /// the difference and both animations land on the same frame.
    static var chipRollDelay: CFTimeInterval { switchDuration - chipRollDuration }

    /// Row 63. The contract's window is 1.1-1.9 s; the brief pins 1.1 s.
    static let keycapDwell: CFTimeInterval = 1.1

    /// Row 63: 83 ms ± 25 ms, opacity monotonic and decelerating.
    static let keycapFadeOut: CFTimeInterval = 0.083

    /// Row 64: 120 ms ± 20 ms.
    static let voiceSendCrossfade: CFTimeInterval = 0.120

    /// Row 82, the exceeds-source press feedback the reference has none of.
    /// `emil-design-eng` puts button press feedback at 100-160 ms and the
    /// scale at 0.95-0.98; the asymmetry (fast in, slower out) is that skill's
    /// "slow where the user decides, fast where the system responds", inverted
    /// here because the press itself is instantaneous.
    static let sendPressIn: CFTimeInterval = 0.100
    static let sendPressOut: CFTimeInterval = 0.160
    static let sendPressScale: CGFloat = 0.97

    /// Row 65: each send effect present within 165 ms ± 25 ms of Return.
    static let sendEffectsDuration: CFTimeInterval = 0.165

    /// Row 65's "input clears one frame later". One frame at the row-112 bar.
    static let oneFrame: CFTimeInterval = 1.0 / 60.0

    /// Row 66: cross-correlation peak between dot 1 and dot 2 at 220 ms ± 60 ms.
    static let workingDotPhase: CFTimeInterval = 0.220
    static let workingDotCount: Int = 3

    /// Row 113. Reduced motion still has to settle inside row 52's budget, so
    /// the cross-fade is shorter than the switch it replaces.
    static let reducedMotionCrossfade: CFTimeInterval = 0.250

    /// Row 115: the centre card is live again within 100 ms of settle. U2 fires
    /// the settle callback; U1's `CarouselLiveSwapCoordinator` consumes this
    /// budget. The constant lives here so both units read one number.
    static let liveSwapBudget: CFTimeInterval = 0.100

    // MARK: - Track recoil (row 54, D-14's track half)

    /// Row 54: track minimum 0.971 ± 0.008.
    static let recoilTrough: CGFloat = 0.971

    /// The recoil's four phase boundaries as fractions of `switchDuration`,
    /// from row 54's "~65 ms in, ~185 ms out, peaking ~30 % through the
    /// translate". 30 % of 300 ms is 90 ms; a 65 ms descent therefore starts at
    /// 25 ms, and a 185 ms return ends at 275 ms. Starting the descent at t=0
    /// instead would put the trough at 21.7 %, which sits on the edge of row
    /// 54's 30 % ± 10 % tolerance for no reason.
    static let recoilHoldInFraction: CGFloat = 25.0 / 300.0
    static let recoilTroughFraction: CGFloat = 90.0 / 300.0
    static let recoilReturnFraction: CGFloat = 275.0 / 300.0

    // MARK: - Per-card scale ramp (row 55, D-14's card half)

    /// D-2 / row 23: the flank scale, the reference's own measured value.
    static let flankScale: CGFloat = 0.94
    static let centreScale: CGFloat = 1.0

    // MARK: - Keycap geometry (row 36), as ratios of window width W

    /// Row 36: 40 x 38 CSS at W = 1344, radius ~11 CSS, 6.5 CSS apart. Held as
    /// ratios per the contract's normalization rule, so nothing voids when the
    /// window is not exactly 1344 wide.
    static let keycapWidthRatio: CGFloat = 0.0298
    static let keycapHeightRatio: CGFloat = 0.0283
    static let keycapRadiusRatio: CGFloat = 11.0 / 1344.0
    static let keycapSpacingRatio: CGFloat = 6.5 / 1344.0
}

/// The one reduce-motion gate for U2 and U6 (row 113).
///
/// The repo has three scattered `accessibilityDisplayShouldReduceMotion` reads
/// and no app-wide convention, so this unit establishes one. It is a closure
/// rather than a protocol because there is exactly one production
/// implementation and the seam exists only so a test can force the flag —
/// rule 37's ladder rung against an interface with a single implementor.
/// Always injected explicitly, never defaulted at a call site. A default
/// argument is evaluated in a nonisolated context, so `= CarouselReduceMotion()`
/// on a main-actor initialiser is a strict-concurrency error rather than a
/// convenience — and requiring it named also means no unit can forget row 113
/// by leaving the parameter off.
@MainActor
struct CarouselReduceMotion {
    private let read: @MainActor () -> Bool

    init(read: @escaping @MainActor () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.read = read
    }

    /// Fixed value, for tests and for the row-113 probe scenario.
    static func fixed(_ value: Bool) -> CarouselReduceMotion {
        CarouselReduceMotion { value }
    }

    var isEnabled: Bool { read() }
}

/// Applies model changes and their animations in ONE Core Animation
/// transaction, with implicit actions off.
///
/// Splitting the two is a real defect, not a style point. A separate
/// `CATransaction` around the model write commits model-only state to the
/// render server before the animation is attached, and the probe reads exactly
/// that: on the frame of a re-target the track's presentation translation jumps
/// the full pitch and comes back on the next frame. The two commits normally
/// coalesce inside one run-loop turn, so it is a hazard rather than a
/// guaranteed visible snap — but it is free to remove and it makes every
/// presentation-value measurement honest.
///
/// Disabling actions also stops Core Animation's default action from attaching
/// its own 0.25 s animation to a property being set on a standalone layer, which
/// silently replaced the keycap's 83 ms fade with a 250 ms one.
@MainActor
func carouselCommit(_ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body()
    CATransaction.commit()
}

/// The same, plus a completion that fires when **the animations added inside
/// `body` have finished** — not when a wall-clock timer says they should have.
///
/// This is what row 115's settle hangs off. A timer racing the compositor was
/// measurably wrong in both directions against U2's own probe data (3.7 ms late
/// on a single switch, 14.3 ms early on a five-press burst), and the thing it
/// gates is mounting a live libghostty terminal. Core Animation already knows
/// exactly when its own animations end; ask it instead of guessing.
///
/// `setCompletionBlock` fires immediately at commit when the transaction added
/// no animations, which is the correct behaviour for a no-op switch.
@MainActor
func carouselCommit(completion: @escaping @MainActor () -> Void, _ body: () -> Void) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
    body()
    CATransaction.commit()
}
