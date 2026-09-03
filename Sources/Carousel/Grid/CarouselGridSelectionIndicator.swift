// Modified 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 80, 83, 113.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore

/// CONTRACT row 80 (X4): grid mode has a visible selection indicator; the
/// source has none.
///
/// VIDEO-REVIEW section 1.7 measured per-card border luminance in the source's
/// grid at 42.4 / 35.6 / 33.1 / 82.3 / 51.9 / 57.3 — the spread tracks the
/// wallpaper behind each card, not selection, and the only cue to which session
/// is current is the prompt-bar chip. Row 80 requires the selected card's
/// border to exceed every other by at least 20 luminance. A white rim at 0.92
/// alpha reads around 235 against a worst case of 82, which clears the bar by
/// an order of magnitude rather than by a margin that a different wallpaper
/// could erase.
///
/// It introduces no new fill, radius or type size (CONTRACT row 70): the radius
/// is the card's own, scaled with the card, and the rim is the same treatment
/// as the card's existing hairline at a higher alpha.
@MainActor
final class CarouselGridSelectionIndicator {
    /// Rim thickness at the reference width, in CSS px.
    private static let rimWidthAtReference: CGFloat = 2
    /// How far the rim sits outside the card's edge, so it reads as a ring
    /// around the card and never crops the card's own content.
    private static let rimInsetAtReference: CGFloat = 3

    let layer: CALayer

    private var isAttached = false

    init() {
        let layer = CALayer()
        layer.name = "carousel.grid.selection"
        layer.backgroundColor = NSColor.clear.cgColor
        layer.borderColor = NSColor.white.withAlphaComponent(0.92).cgColor
        layer.opacity = 0
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "opacity": NSNull()]
        self.layer = layer
    }

    /// Places the ring around `cardRect`, expressed in the host's layer
    /// coordinate space.
    func ringFrame(around cardRect: CGRect, geometry: CarouselOverlayGeometry) -> CGRect {
        let inset = geometry.scaled(Self.rimInsetAtReference)
        return cardRect.insetBy(dx: -inset, dy: -inset)
    }

    func configure(geometry: CarouselOverlayGeometry, gridCardWidth: CGFloat) {
        layer.borderWidth = geometry.scaled(Self.rimWidthAtReference)
        // The card's radius scaled by the same factor the card is, plus the rim
        // inset, so the ring's curvature matches the card it surrounds.
        let cardScale = geometry.centreCardRect.width > 0 ? gridCardWidth / geometry.centreCardRect.width : 1
        layer.cornerRadius = geometry.cardCornerRadius * cardScale + geometry.scaled(Self.rimInsetAtReference)
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
    }

    func attach(to host: CALayer) {
        guard !isAttached else { return }
        isAttached = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.addSublayer(layer)
        CATransaction.commit()
    }

    /// CONTRACT row 83 (X7): nothing an overlay drew may survive its close. The
    /// ring is removed from the tree, not merely hidden, and every animation on
    /// it is dropped so no fill-mode remnant can paint after removal.
    func detach() {
        guard isAttached else { return }
        isAttached = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAllAnimations()
        layer.opacity = 0
        layer.removeFromSuperlayer()
        CATransaction.commit()
    }

    /// Moves the ring to a new card. Retargets from the presentation value so a
    /// held arrow key slides continuously instead of restarting from the last
    /// target, and cross-fades instead of sliding under reduced motion.
    func move(to targetFrame: CGRect, animated: Bool) {
        let presentation = layer.presentation()
        let fromPosition = presentation?.position ?? layer.position
        let fromBounds = presentation?.bounds ?? layer.bounds

        if CarouselOverlayMotion.reduceMotion, animated {
            // Geometry changes only while the ring is invisible: fade out,
            // snap, fade back in. The previous shape committed the geometry
            // at full opacity first and only then blinked — a teleport with
            // a blink on top, which row 113's letter cannot see but a viewer
            // can (row 80/113, ruling (d) A1).
            let half = CarouselOverlayMotion.reducedCrossFade / 2
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = presentation?.opacity ?? layer.opacity
            out.toValue = 0
            out.duration = half
            out.timingFunction = CarouselOverlayMotion.easeOut
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.layer.bounds = CGRect(origin: .zero, size: targetFrame.size)
                self.layer.position = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
                CATransaction.commit()
                let inn = CABasicAnimation(keyPath: "opacity")
                inn.fromValue = 0
                inn.toValue = 1
                inn.duration = half
                inn.timingFunction = CarouselOverlayMotion.easeOut
                self.layer.add(inn, forKey: "carousel.grid.selection.opacity")
            }
            layer.add(out, forKey: "carousel.grid.selection.opacity")
            CATransaction.commit()
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds = CGRect(origin: .zero, size: targetFrame.size)
        layer.position = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
        CATransaction.commit()

        guard animated else {
            layer.removeAnimation(forKey: "carousel.grid.selection.position")
            layer.removeAnimation(forKey: "carousel.grid.selection.bounds")
            return
        }

        let position = CABasicAnimation(keyPath: "position")
        position.fromValue = NSValue(point: fromPosition)
        position.duration = CarouselOverlayMotion.selectionMove
        position.timingFunction = CarouselOverlayMotion.easeOut
        layer.add(position, forKey: "carousel.grid.selection.position")

        let bounds = CABasicAnimation(keyPath: "bounds")
        bounds.fromValue = NSValue(rect: fromBounds)
        bounds.duration = CarouselOverlayMotion.selectionMove
        bounds.timingFunction = CarouselOverlayMotion.easeOut
        layer.add(bounds, forKey: "carousel.grid.selection.bounds")
    }

    func setVisible(_ visible: Bool, animated: Bool, duration: CFTimeInterval) {
        let presentation = layer.presentation()
        let from = presentation?.opacity ?? layer.opacity
        let to: Float = visible ? 1 : 0

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = to
        CATransaction.commit()

        guard animated, from != to else {
            layer.removeAnimation(forKey: "carousel.grid.selection.fade")
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.duration = duration
        fade.timingFunction = CarouselOverlayMotion.easeOut
        layer.add(fade, forKey: "carousel.grid.selection.fade")
    }
}
