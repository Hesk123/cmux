import AppKit
import QuartzCore

/// The prompt bar's action control and the visual half of a send: rows 64, 65
/// and 82.
///
/// # Row 64 is enforced structurally, not by tolerance
///
/// "The circle never changes size, colour or position" is guaranteed by this
/// type never holding a reference it could animate: it is given the two icon
/// layers and nothing else. The circle cannot drift because nothing here can
/// reach it. That is cheaper and more durable than asserting a tolerance on a
/// value some later edit might start animating.
@MainActor
final class CarouselSendFeedback {

    enum Mode {
        case voice
        case send
    }

    private let pressTarget: CALayer
    private let voiceIcon: CALayer
    private let sendIcon: CALayer
    private let suggestionChips: [CALayer]
    private let reduceMotion: CarouselReduceMotion

    private var mode: Mode = .voice

    /// Row 47's chips at rest, so a dim can be undone without a second constant.
    private let chipRestingOpacity: Float
    private let chipDimmedOpacity: Float

    /// - Parameters:
    ///   - pressTarget: the layer that carries row 82's press scale. This is the
    ///     control's content, not the blue circle: scaling the circle would
    ///     violate row 64's "never changes size".
    init(
        pressTarget: CALayer,
        voiceIcon: CALayer,
        sendIcon: CALayer,
        suggestionChips: [CALayer],
        chipRestingOpacity: Float = 1.0,
        chipDimmedOpacity: Float = 0.4,
        reduceMotion: CarouselReduceMotion
    ) {
        self.pressTarget = pressTarget
        self.voiceIcon = voiceIcon
        self.sendIcon = sendIcon
        self.suggestionChips = suggestionChips
        self.chipRestingOpacity = chipRestingOpacity
        self.chipDimmedOpacity = chipDimmedOpacity
        self.reduceMotion = reduceMotion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        voiceIcon.opacity = 1
        sendIcon.opacity = 0
        CATransaction.commit()
    }

    /// Row 64: icon crossfade only, ~120 ms ease-out. Called when the input
    /// becomes non-empty and again when it empties.
    func setMode(_ newMode: Mode) {
        guard newMode != mode else { return }
        mode = newMode
        let showing = newMode == .send ? sendIcon : voiceIcon
        let hiding = newMode == .send ? voiceIcon : sendIcon
        fade(showing, to: 1, duration: CarouselMotion.voiceSendCrossfade)
        fade(hiding, to: 0, duration: CarouselMotion.voiceSendCrossfade)
    }

    /// Row 82, the exceeds-source press feedback. Driven by Return as well as by
    /// a click, because row 82 asserts the dip within 2 frames of the *Return
    /// event* — the reference has no feedback at all, and a mouse-only version
    /// would leave the keyboard path, which is the one Dawid actually uses,
    /// with none either.
    ///
    /// Suppressed under reduced motion: it is a pure scale change, which is
    /// what row 113 removes, and it carries no information the send's other
    /// four effects do not.
    func flashPress() {
        guard !reduceMotion.isEnabled else { return }

        let down = CABasicAnimation(keyPath: "transform.scale")
        down.fromValue = presentationScale() ?? 1
        down.toValue = CarouselMotion.sendPressScale
        down.duration = CarouselMotion.sendPressIn
        down.timingFunction = CarouselMotion.switchCurve

        let up = CABasicAnimation(keyPath: "transform.scale")
        up.fromValue = CarouselMotion.sendPressScale
        up.toValue = 1
        up.beginTime = CarouselMotion.sendPressIn
        up.duration = CarouselMotion.sendPressOut
        up.timingFunction = CarouselMotion.switchCurve

        let group = CAAnimationGroup()
        group.animations = [down, up]
        group.duration = CarouselMotion.sendPressIn + CarouselMotion.sendPressOut
        pressTarget.add(group, forKey: "press")
    }

    /// Row 65's U2 half: the chips dim, and the input clears one frame later.
    ///
    /// The pty echo and the surface auto-scroll are U3's, since they are writes
    /// to the centred surface rather than motion. `clearInput` is handed back
    /// so U3 owns the text field and this unit owns only when it happens.
    func didSend(clearInput: @escaping @MainActor () -> Void) {
        flashPress()
        for chip in suggestionChips {
            fade(chip, to: chipDimmedOpacity, duration: CarouselMotion.sendEffectsDuration)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(CarouselMotion.oneFrame * 1000)))
            clearInput()
        }
    }

    /// The generation finished: row 47's chips come back.
    func didFinishGenerating() {
        for chip in suggestionChips {
            fade(chip, to: chipRestingOpacity, duration: CarouselMotion.sendEffectsDuration)
        }
    }

    private func fade(_ layer: CALayer, to target: Float, duration: CFTimeInterval) {
        let step = CABasicAnimation(keyPath: "opacity")
        step.fromValue = layer.presentation()?.opacity ?? layer.opacity
        step.toValue = target
        step.duration = duration
        step.timingFunction = CarouselMotion.switchCurve
        layer.add(step, forKey: "opacity")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = target
        CATransaction.commit()
    }

    private func presentationScale() -> CGFloat? {
        guard let number = pressTarget.presentation()?.value(forKeyPath: "transform.scale") as? NSNumber else {
            return nil
        }
        return CGFloat(number.doubleValue)
    }
}
