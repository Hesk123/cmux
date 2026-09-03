// Added 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 37, 67, 68, 78, 83, 113, 123.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore

/// Presents toasts in the top-right slot: enter, dwell, exit.
///
/// * **Enter, CONTRACT row 67.** Slide from off-screen right over 330 ms with a
///   strong ease-out, y fixed, opacity ramping, no overshoot. The curve's
///   control points are both at y = 1, so the value cannot pass its target, and
///   its derivative decreases monotonically — which is exactly what row 67
///   asserts frame by frame.
/// * **Dwell, CONTRACT row 68.** 3.6 s, measured on a monotonic clock and
///   pausable. It pauses while the pointer is inside the toast and while the
///   window is occluded or not key, so a toast is never spent on a screen
///   nobody is looking at. That is Sonner's fourth principle; it is invisible
///   when it works, which is the point.
/// * **Exit, CONTRACT row 78 (X2).** The reference hard-cuts all three of its
///   toasts out of existence in a single frame — VIDEO-REVIEW section 2.9,
///   verified at 23.4, 33.7 and 39.7 s. This one leaves the way it arrived, to
///   the right, over 200 ms: same path in and out, so the motion reads as one
///   object rather than two events, and faster out than in because the system
///   is responding rather than the user deciding.
/// * **Replace.** VIDEO-REVIEW section 2.9 records that toasts replace each
///   other in the same slot rather than stacking. A toast arriving while one is
///   presented cuts the dwell short, plays the exit, then plays the entrance of
///   the new one — so the slot is never occupied by two things at once and the
///   replacement is still animated at both ends.
@MainActor
final class CarouselToastPresenter {
    private enum Phase: Equatable {
        case idle
        case entering
        case dwelling
        case exiting
    }

    private static let translateKey = "carousel.toast.translate"
    private static let opacityKey = "carousel.toast.opacity"

    private weak var host: NSView?
    private var geometry: CarouselOverlayGeometry

    private var view: CarouselToastView?
    private(set) var currentToast: CarouselToast?
    private var pending: [CarouselToast] = []

    private var phase: Phase = .idle
    private var generation: UInt64 = 0

    private var dwellRemaining: CFTimeInterval = 0
    private var dwellResumedAt: CFTimeInterval = 0
    private var dwellTimer: Timer?
    private var isHovered = false
    private var isWindowVisible = true

    /// Test seam. Fires when a toast has fully settled at its slot, and again
    /// when it has fully left, so the dwell can be timed without polling.
    var onSettled: ((CarouselToast) -> Void)?
    /// Fires the moment the dwell ends and the exit animation is added, so the
    /// dwell can be timed directly instead of inferred by subtracting the exit
    /// duration from the dismissal.
    var onExitBegan: ((CarouselToast) -> Void)?
    var onDismissed: ((CarouselToast) -> Void)?

    init(host: NSView?, geometry: CarouselOverlayGeometry) {
        self.host = host
        self.geometry = geometry
    }

    var isPresenting: Bool { phase != .idle }
    var presentedView: CarouselToastView? { view }

    func setGeometry(_ geometry: CarouselOverlayGeometry) {
        self.geometry = geometry
        if let view, let toast = currentToast {
            view.frame = geometry.toastRect(width: view.preferredWidth(for: toast))
            view.layOutContents()
        }
    }

    // MARK: - Presenting

    func present(_ toast: CarouselToast) {
        guard host != nil else { return }
        switch phase {
        case .idle:
            show(toast)
        case .entering, .dwelling:
            pending.append(toast)
            beginExit()
        case .exiting:
            pending.append(toast)
        }
    }

    private func show(_ toast: CarouselToast) {
        guard let host else { return }
        generation &+= 1
        let currentGeneration = generation

        let toastView = view ?? CarouselToastView(geometry: geometry)
        // Anchored top-right at its own content width, never at a fixed one.
        toastView.frame = geometry.toastRect(width: toastView.preferredWidth(for: toast))
        toastView.layOutContents()
        toastView.apply(toast)
        toastView.applyTransparencySetting()
        toastView.onHoverChanged = { [weak self] hovered in
            self?.setHovered(hovered)
        }
        if toastView.superview == nil {
            host.addSubview(toastView)
        }
        view = toastView
        currentToast = toast
        phase = .entering

        guard let layer = toastView.layer else { return }
        let reduced = CarouselOverlayMotion.reduceMotion
        let offset = offscreenOffset()

        let fromTranslation: CGFloat = reduced ? 0 : offset
        let fromOpacity = layer.presentation()?.opacity ?? 0
        let duration = reduced ? CarouselOverlayMotion.reducedCrossFade : CarouselOverlayMotion.toastIn

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DIdentity
        layer.opacity = 1
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishEntrance(generation: currentGeneration)
            }
        }
        if !reduced {
            let translate = CABasicAnimation(keyPath: "transform.translation.x")
            translate.fromValue = fromTranslation
            translate.toValue = 0
            translate.duration = duration
            translate.timingFunction = CarouselOverlayMotion.easeOut
            layer.add(translate, forKey: Self.translateKey)
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CarouselOverlayMotion.easeOut
        layer.add(fade, forKey: Self.opacityKey)
        CATransaction.commit()
    }

    /// Fully off-screen right: the pill's left edge starts at the viewport's
    /// right edge, so no part of it is ever clipped mid-slide.
    private func offscreenOffset() -> CGFloat {
        guard let view else { return geometry.viewport.width }
        return geometry.viewport.width - view.frame.minX
    }

    private func finishEntrance(generation currentGeneration: UInt64) {
        guard currentGeneration == generation, phase == .entering else { return }
        phase = .dwelling
        dwellRemaining = CarouselOverlayMotion.toastDwell
        resumeDwellIfAllowed()
        if let currentToast { onSettled?(currentToast) }
    }

    // MARK: - Dwell

    private func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        if hovered { pauseDwell() } else { resumeDwellIfAllowed() }
    }

    /// Wired by the carousel host to `NSApplication.didChangeOcclusionStateNotification`
    /// in one line at integration (MAKER-U6.md, section Integration). It lives
    /// here as an input rather than as an observer the presenter installs
    /// itself, so the presenter owns no notification registration and needs no
    /// `deinit` — one fewer thing to get wrong under strict concurrency, and
    /// the pause is drivable directly from a test.
    func setWindowVisible(_ visible: Bool) {
        guard isWindowVisible != visible else { return }
        isWindowVisible = visible
        if visible { resumeDwellIfAllowed() } else { pauseDwell() }
    }

    private func resumeDwellIfAllowed() {
        guard phase == .dwelling, !isHovered, isWindowVisible, dwellTimer == nil else { return }
        guard dwellRemaining > 0 else { beginExit(); return }
        dwellResumedAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: dwellRemaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dwellElapsed()
            }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        dwellTimer = timer
    }

    private func pauseDwell() {
        guard let timer = dwellTimer else { return }
        timer.invalidate()
        dwellTimer = nil
        dwellRemaining = max(0, dwellRemaining - (CACurrentMediaTime() - dwellResumedAt))
    }

    private func dwellElapsed() {
        dwellTimer = nil
        dwellRemaining = 0
        guard phase == .dwelling else { return }
        beginExit()
    }

    // MARK: - Exit

    func dismiss() {
        guard phase == .entering || phase == .dwelling else { return }
        beginExit()
    }

    private func beginExit() {
        guard let layer = view?.layer, phase != .exiting, phase != .idle else { return }
        pauseDwell()
        dwellTimer = nil
        phase = .exiting
        generation &+= 1
        let currentGeneration = generation

        let reduced = CarouselOverlayMotion.reduceMotion
        let duration = reduced ? CarouselOverlayMotion.reducedCrossFade : CarouselOverlayMotion.toastOut
        let presentation = layer.presentation()
        // Read the translation off the presentation transform directly. Going
        // through value(forKeyPath:) returns an NSNumber, so an `as? CGFloat`
        // silently yields nil and the exit would restart from zero — a visible
        // jump every time a toast is replaced mid-entrance, which is the exact
        // discontinuity the presentation-value rule exists to prevent.
        let fromTranslation = presentation?.transform.m41 ?? layer.transform.m41
        let fromOpacity = presentation?.opacity ?? layer.opacity
        let offset = offscreenOffset()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = reduced ? CATransform3DIdentity : CATransform3DMakeTranslation(offset, 0, 0)
        layer.opacity = 0
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishExit(generation: currentGeneration)
            }
        }
        if !reduced {
            let translate = CABasicAnimation(keyPath: "transform.translation.x")
            translate.fromValue = fromTranslation
            translate.toValue = offset
            translate.duration = duration
            translate.timingFunction = CarouselOverlayMotion.easeOut
            layer.add(translate, forKey: Self.translateKey)
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = fromOpacity
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CarouselOverlayMotion.easeOut
        layer.add(fade, forKey: Self.opacityKey)
        CATransaction.commit()

        if let currentToast { onExitBegan?(currentToast) }
    }

    /// CONTRACT row 83 (X7): the view leaves the hierarchy, it is not left
    /// hidden. A hidden view with a fill-mode animation still on it is the
    /// shape of the reference's lingering wireframe.
    private func finishExit(generation currentGeneration: UInt64) {
        guard currentGeneration == generation, phase == .exiting else { return }
        let dismissed = currentToast
        view?.layer?.removeAllAnimations()
        view?.removeFromSuperview()
        view = nil
        currentToast = nil
        phase = .idle
        if let dismissed { onDismissed?(dismissed) }
        if !pending.isEmpty {
            show(pending.removeFirst())
        }
    }

    /// Test seam for row 83: zero after any close.
    var residualSubviewCount: Int {
        guard let host else { return 0 }
        return host.subviews.filter { $0 is CarouselToastView }.count
    }
}
