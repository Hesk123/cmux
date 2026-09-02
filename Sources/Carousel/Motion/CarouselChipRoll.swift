import AppKit
import QuartzCore

/// The prompt bar's session chip: rows 58, 59, 60 and 79.
///
/// The new label enters from one edge of the pill, the old leaves by the other,
/// both cross-fading, both clipped by the pill's rounded background, while the
/// pill's width animates to the new label as part of the same motion.
///
/// # Row 79 — the one place this deliberately departs from the source
///
/// VIDEO-REVIEW §2.2 measured the reference's roll as **not** direction-aware:
/// a backward switch rolls the new label in from the top exactly as a forward
/// one does. That is gap G3, and row 79 fixes it: forward enters from the top,
/// backward from the bottom, so the chip agrees with the direction the cards
/// just travelled. `apple-design`'s spatial-consistency rule is the reason —
/// a thing that leaves one way should come back the other way, and a roll that
/// always falls downward while the carousel moves both ways breaks the
/// mapping between the gesture and what it did.
@MainActor
final class CarouselChipRoll {

    enum Direction {
        case forward
        case backward

        /// Where the incoming label starts, as a multiple of the pill height.
        /// Layer coordinates are y-up, so a forward roll starts the new label
        /// above the slot and pushes the old one down and out.
        var entryOffsetSign: CGFloat {
            switch self {
            case .forward: 1
            case .backward: -1
            }
        }
    }

    private let pill: CALayer
    private let makeLabel: @MainActor (String) -> CALayer
    private let reduceMotion: CarouselReduceMotion

    private var currentLabel: CALayer?
    private var retiring: [CALayer] = []

    /// - Parameters:
    ///   - pill: the chip background. Must have `masksToBounds` true so the
    ///     labels are clipped by it (row 58), and an `anchorPoint` whose x is 0
    ///     if the chip is left-aligned in the prompt bar, so the row-60 width
    ///     animation grows rightwards instead of from the centre.
    ///   - makeLabel: builds a label layer for a session name. U3 owns the type
    ///     and metrics of that layer; this unit only moves it.
    init(
        pill: CALayer,
        makeLabel: @escaping @MainActor (String) -> CALayer,
        reduceMotion: CarouselReduceMotion
    ) {
        self.pill = pill
        self.makeLabel = makeLabel
        self.reduceMotion = reduceMotion
    }

    /// Places the first label with no animation, for the initial paint.
    func setInitial(_ text: String, pillWidth: CGFloat) {
        currentLabel?.removeFromSuperlayer()
        let label = makeLabel(text)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pill.addSublayer(label)
        pill.bounds.size.width = pillWidth
        CATransaction.commit()
        currentLabel = label
    }

    /// Rolls to `text`, settling on the same frame as the card translate.
    func roll(to text: String, pillWidth: CGFloat, direction: Direction) {
        let outgoing = currentLabel
        let incoming = makeLabel(text)
        pill.addSublayer(incoming)
        currentLabel = incoming

        guard !reduceMotion.isEnabled else {
            crossFadeOnly(incoming: incoming, outgoing: outgoing, pillWidth: pillWidth)
            return
        }

        let travel = pill.bounds.height * direction.entryOffsetSign
        let begin = CACurrentMediaTime() + CarouselMotion.chipRollDelay

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.setValue(travel, forKeyPath: "transform.translation.y")
        incoming.opacity = 0
        CATransaction.commit()

        animate(incoming, keyPath: "transform.translation.y", from: travel, to: 0, begin: begin, duration: CarouselMotion.chipRollDuration)
        animate(incoming, keyPath: "opacity", from: 0, to: 1, begin: begin, duration: CarouselMotion.chipRollDuration)

        if let outgoing {
            // Start from what is on screen, not from rest: a second press
            // during a roll must not snap the half-rolled label back first.
            let y = presentation(outgoing, keyPath: "transform.translation.y") ?? 0
            let alpha = presentation(outgoing, keyPath: "opacity") ?? 1
            animate(outgoing, keyPath: "transform.translation.y", from: y, to: -travel, begin: begin, duration: CarouselMotion.chipRollDuration)
            animate(outgoing, keyPath: "opacity", from: alpha, to: 0, begin: begin, duration: CarouselMotion.chipRollDuration)
            retire(outgoing, after: CarouselMotion.chipRollDelay + CarouselMotion.chipRollDuration)
        }

        // Row 60. Animating `bounds.size.width` rather than the frame keeps the
        // pill's own anchoring in charge of which edge moves.
        let width = presentation(pill, keyPath: "bounds.size.width") ?? pill.bounds.width
        animate(pill, keyPath: "bounds.size.width", from: width, to: pillWidth, begin: begin, duration: CarouselMotion.chipRollDuration)
    }

    /// Row 113: no translation and no width animation, opacity only.
    private func crossFadeOnly(incoming: CALayer, outgoing: CALayer?, pillWidth: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.setValue(0, forKeyPath: "transform.translation.y")
        incoming.opacity = 0
        pill.bounds.size.width = pillWidth
        CATransaction.commit()

        animate(
            incoming,
            keyPath: "opacity",
            from: 0,
            to: 1,
            begin: CACurrentMediaTime(),
            duration: CarouselMotion.reducedMotionCrossfade
        )
        if let outgoing {
            let alpha = presentation(outgoing, keyPath: "opacity") ?? 1
            animate(
                outgoing,
                keyPath: "opacity",
                from: alpha,
                to: 0,
                begin: CACurrentMediaTime(),
                duration: CarouselMotion.reducedMotionCrossfade
            )
            retire(outgoing, after: CarouselMotion.reducedMotionCrossfade)
        }
    }

    private func animate(
        _ layer: CALayer,
        keyPath: String,
        from: CGFloat,
        to: CGFloat,
        begin: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        let step = CABasicAnimation(keyPath: keyPath)
        step.fromValue = from
        step.toValue = to
        step.duration = duration
        step.beginTime = begin
        step.timingFunction = CarouselMotion.switchCurve
        // The label must not flash at its resting value during the delay before
        // the roll starts, so the from-value is held backwards from beginTime.
        step.fillMode = .backwards
        layer.add(step, forKey: keyPath)

        // The model has to end up at the target for EVERY key path, not just
        // opacity. Core Animation removes a finished animation and then renders
        // the model value, so a label whose model y is still its entry offset
        // snaps back up the instant the roll completes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(to, forKeyPath: keyPath)
        CATransaction.commit()
    }

    private func presentation(_ layer: CALayer, keyPath: String) -> CGFloat? {
        guard let number = layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber else {
            return nil
        }
        return CGFloat(number.doubleValue)
    }

    private func retire(_ layer: CALayer, after delay: CFTimeInterval) {
        retiring.append(layer)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            layer.removeFromSuperlayer()
            self?.retiring.removeAll { $0 === layer }
        }
    }
}
