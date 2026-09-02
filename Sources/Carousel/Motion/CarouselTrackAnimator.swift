import AppKit
import QuartzCore

/// The carousel switch: row 52's 300 ms translate, row 54's track-level recoil,
/// row 55's per-card scale ramp, row 56's mid-flight re-target and row 113's
/// reduced-motion cross-fade.
///
/// # The two-layer split, and why it is two layers
///
/// D-14 rules that the recoil and the per-card ramp are **two transforms that
/// compose**, and that the rendered scale of any card is `track x card`. That
/// is expressed structurally rather than by arithmetic:
///
///     recoilLayer     anchor = viewport centre, holds ONLY transform.scale
///       trackLayer    holds ONLY transform.translation.x
///         cardLayer   holds ONLY its own transform.scale (0.94 or 1.0)
///
/// Putting the recoil on its own layer, anchored at the viewport centre, is
/// what makes the dip scale the carousel about the centred card instead of
/// about the track's leading edge. Putting the translation on a separate inner
/// layer keeps the pitch in screen units: a scale above a translation would
/// shrink the displacement too, and row 52 asserts the centre travels exactly
/// one pitch.
///
/// It also gives row 54 its stated observable for free. Every visible card
/// shares one recoil value in every frame because they share one ancestor, and
/// a card not adjacent to the centre keeps `c = 0.94` because this animator
/// never touches it — which is the card row 54 says the harness solves the
/// two-unknown equation from.
///
/// # Interruption
///
/// Every animation here is **additive** (`CABasicAnimation.isAdditive`). On a
/// re-target the model value jumps to the new target and a fresh animation
/// carries the delta `oldTarget - newTarget` down to zero, so the composite at
/// the instant of interruption is exactly the value already on screen and the
/// still-running animation keeps decaying underneath. Velocities sum instead of
/// being replaced, which is `apple-design`'s rule against the "brick wall" a
/// hard cut creates at a reversal, and it is Core Animation's own form of the
/// additive animations that ruling cites from iOS.
///
/// Two properties fall out of it that a replace-from-presentation scheme does
/// not give: the endpoint is exact (every additive decays to zero on top of a
/// model value that is already the target, so row 56's "two pitches +/- 2 px"
/// cannot drift), and no presentation read is needed on the keypress frame.
@MainActor
final class CarouselTrackAnimator {

    /// The layers this animator owns. U1 builds the tree; this type states the
    /// contract the tree has to satisfy and never mutates geometry itself.
    struct Layers {
        /// Anchored at the viewport centre. Carries the row-54 recoil only.
        let recoil: CALayer
        /// Child of `recoil`. Carries the row-52 translation only.
        let track: CALayer
    }

    /// Which of the two ramps a card runs during one switch (row 55).
    /// Every card that is neither entering nor leaving the centre is simply not
    /// passed in, and therefore holds 0.94.
    struct Ramps {
        var entering: CALayer?
        var leaving: CALayer?

        init(entering: CALayer? = nil, leaving: CALayer? = nil) {
            self.entering = entering
            self.leaving = leaving
        }
    }

    private static let recoilKey = "carousel.recoil"
    private static let reducedMotionKey = "carousel.reducedMotion"

    private let layers: Layers
    private let reduceMotion: CarouselReduceMotion

    /// Row 25's slot pitch, in points. Supplied by U1's `CarouselMetrics`; this
    /// unit never stores a second copy of a layout constant.
    private let pitch: CGFloat

    /// Model values. Kept here rather than read back from the layers so a
    /// re-target needs no presentation query on the keypress frame.
    private var translationTarget: CGFloat = 0
    private var cardScaleTargets: [ObjectIdentifier: CGFloat] = [:]

    /// Invalidates the settle callback of a switch that a later press replaced.
    private var generation: Int = 0

    init(layers: Layers, pitch: CGFloat, reduceMotion: CarouselReduceMotion) {
        self.layers = layers
        self.pitch = pitch
        self.reduceMotion = reduceMotion
    }

    /// Builds a layer pair satisfying `Layers`' contract for a given viewport.
    ///
    /// The anchor point is the whole point of the pair, so it is set in one
    /// place rather than restated in U1, in U6 and in the probe.
    static func makeLayers(viewport: CGRect) -> Layers {
        let recoil = CALayer()
        recoil.bounds = CGRect(origin: .zero, size: viewport.size)
        recoil.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        recoil.position = CGPoint(x: viewport.midX, y: viewport.midY)
        recoil.masksToBounds = true

        let track = CALayer()
        track.bounds = recoil.bounds
        track.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        track.position = CGPoint(x: viewport.width / 2, y: viewport.height / 2)
        recoil.addSublayer(track)

        return Layers(recoil: recoil, track: track)
    }

    /// Registers a card layer at its resting scale so a later ramp knows where
    /// it started. U1 calls this as cards are added to the track.
    func register(card: CALayer, scale: CGFloat) {
        cardScaleTargets[ObjectIdentifier(card)] = scale
        setModel(scale, forKeyPath: "transform.scale", on: card)
    }

    func forget(card: CALayer) {
        cardScaleTargets.removeValue(forKey: ObjectIdentifier(card))
    }

    /// Moves the carousel by `slots` positions.
    ///
    /// - Parameters:
    ///   - slots: `+1` centres the next session (the track moves left by one
    ///     pitch), `-1` the previous. Larger magnitudes are a single animation
    ///     to the further target, never a queue (row 56).
    ///   - ramps: the two cards that change scale this switch (row 55).
    ///   - onSettle: fired once the switch has settled and never for a switch a
    ///     later press replaced. U1's live-swap coordinator remounts the live
    ///     centre from here, inside `CarouselMotion.liveSwapBudget` (row 115).
    func advance(by slots: Int, ramps: Ramps, onSettle: @escaping () -> Void) {
        guard slots != 0 else {
            onSettle()
            return
        }

        generation += 1
        let thisGeneration = generation

        let newTranslation = translationTarget - CGFloat(slots) * pitch

        guard !reduceMotion.isEnabled else {
            advanceWithReducedMotion(
                to: newTranslation,
                ramps: ramps,
                generation: thisGeneration,
                onSettle: onSettle
            )
            return
        }

        layers.recoil.removeAnimation(forKey: Self.reducedMotionKey)

        retargetAdditively(
            keyPath: "transform.translation.x",
            on: layers.track,
            from: translationTarget,
            to: newTranslation
        )
        translationTarget = newTranslation

        if let entering = ramps.entering {
            rampCard(entering, to: CarouselMotion.centreScale)
        }
        if let leaving = ramps.leaving {
            rampCard(leaving, to: CarouselMotion.flankScale)
        }

        applyRecoil()
        scheduleSettle(after: CarouselMotion.switchDuration, generation: thisGeneration, onSettle: onSettle)
    }

    /// Row 113. Zero translation animation and zero scale animation: the whole
    /// carousel jumps to its settled state first, then a `CATransition` on the
    /// recoil layer cross-fades the before and after renderings.
    ///
    /// The jump happens *before* the cross-fade rather than during it so that
    /// across the entire animated window every geometric property is constant,
    /// which is what row 113 asserts. `apple-design` calls for exactly this
    /// substitution — a short opacity cross-fade in place of a slide, with the
    /// elastic parts dropped — and the flanks keep their 0.94 delta and all
    /// three cards stay visible, which is row 113's stated end state.
    private func advanceWithReducedMotion(
        to newTranslation: CGFloat,
        ramps: Ramps,
        generation thisGeneration: Int,
        onSettle: @escaping () -> Void
    ) {
        layers.track.removeAllAnimations()
        layers.recoil.removeAllAnimations()
        ramps.entering?.removeAllAnimations()
        ramps.leaving?.removeAllAnimations()

        let fade = CATransition()
        fade.type = .fade
        fade.duration = CarouselMotion.reducedMotionCrossfade
        fade.timingFunction = CarouselMotion.switchCurve
        layers.recoil.add(fade, forKey: Self.reducedMotionKey)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setModel(newTranslation, forKeyPath: "transform.translation.x", on: layers.track)
        setModel(CarouselMotion.centreScale, forKeyPath: "transform.scale", on: layers.recoil)
        if let entering = ramps.entering {
            cardScaleTargets[ObjectIdentifier(entering)] = CarouselMotion.centreScale
            setModel(CarouselMotion.centreScale, forKeyPath: "transform.scale", on: entering)
        }
        if let leaving = ramps.leaving {
            cardScaleTargets[ObjectIdentifier(leaving)] = CarouselMotion.flankScale
            setModel(CarouselMotion.flankScale, forKeyPath: "transform.scale", on: leaving)
        }
        CATransaction.commit()

        translationTarget = newTranslation
        scheduleSettle(
            after: CarouselMotion.reducedMotionCrossfade,
            generation: thisGeneration,
            onSettle: onSettle
        )
    }

    // MARK: - Row 54, the track recoil

    /// One keyframe over the full switch duration, so the dip is phase-locked
    /// to the translate by construction and a re-target moves both together.
    ///
    /// Unlike the translate this is replaced rather than accumulated. Two
    /// overlapping additive dips would sum to roughly 0.942 during a fast
    /// burst, which is both outside row 54's 0.971 +/- 0.008 and visibly wrong.
    /// Continuity is kept instead by starting the new keyframe at the value
    /// currently on screen.
    private func applyRecoil() {
        let current = presentationValue(forKeyPath: "transform.scale", on: layers.recoil)
            ?? CarouselMotion.centreScale
        layers.recoil.removeAnimation(forKey: Self.recoilKey)

        let dip = CAKeyframeAnimation(keyPath: "transform.scale")
        // Explicit NSNumbers: `values` is `[Any]?`, and a CGFloat that only
        // bridges on read is a silent way for a harness cast to come back nil.
        dip.values = [
            current,
            current,
            CarouselMotion.recoilTrough,
            CarouselMotion.centreScale,
            CarouselMotion.centreScale,
        ].map { NSNumber(value: Double($0)) }
        dip.keyTimes = [
            0,
            CarouselMotion.recoilHoldInFraction,
            CarouselMotion.recoilTroughFraction,
            CarouselMotion.recoilReturnFraction,
            1,
        ].map { NSNumber(value: Double($0)) }
        dip.timingFunctions = [
            CarouselMotion.linearCurve,
            CarouselMotion.recoilInCurve,
            CarouselMotion.switchCurve,
            CarouselMotion.linearCurve,
        ]
        dip.duration = CarouselMotion.switchDuration
        layers.recoil.add(dip, forKey: Self.recoilKey)
    }

    // MARK: - Row 55, the per-card ramp

    private func rampCard(_ card: CALayer, to scale: CGFloat) {
        let key = ObjectIdentifier(card)
        let old = cardScaleTargets[key] ?? CarouselMotion.flankScale
        guard old != scale else { return }
        retargetAdditively(keyPath: "transform.scale", on: card, from: old, to: scale)
        cardScaleTargets[key] = scale
    }

    // MARK: - Additive re-target

    private func retargetAdditively(
        keyPath: String,
        on layer: CALayer,
        from oldTarget: CGFloat,
        to newTarget: CGFloat
    ) {
        setModel(newTarget, forKeyPath: keyPath, on: layer)

        let move = CABasicAnimation(keyPath: keyPath)
        move.isAdditive = true
        move.fromValue = oldTarget - newTarget
        move.toValue = 0
        move.duration = CarouselMotion.switchDuration
        move.timingFunction = CarouselMotion.switchCurve
        // A nil key accumulates. Naming it would replace the in-flight
        // animation, which is the very thing additivity exists to avoid.
        layer.add(move, forKey: nil)
    }

    private func setModel(_ value: CGFloat, forKeyPath keyPath: String, on layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
    }

    private func presentationValue(forKeyPath keyPath: String, on layer: CALayer) -> CGFloat? {
        guard let number = layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber else {
            return nil
        }
        return CGFloat(number.doubleValue)
    }

    private func scheduleSettle(
        after delay: CFTimeInterval,
        generation thisGeneration: Int,
        onSettle: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            guard let self, self.generation == thisGeneration else { return }
            onSettle()
        }
    }
}
