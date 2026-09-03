// Added 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 38-40, 77, 80, 83, 112, 113.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore

/// Grid mode, and the shared-element transition into and out of it.
///
/// CONTRACT row 77 (X1) is the reason this type exists: VIDEO-REVIEW section
/// 2.7 measured all six of the reference's grid toggles as single-frame hard
/// cuts, a 25-30 diff spike on exactly one frame with quiet either side. Rows
/// 39 and 40 make the fix cheap — the grid block and the carousel card already
/// share a vertical centre, and the grid card's aspect is the carousel card's —
/// so each card's carousel rect maps onto its grid rect by a **uniform scale
/// plus a translation**, with no bounds change and therefore no relayout of
/// anything the card hosts.
///
/// Only `position` and `transform` animate. Nothing here touches `bounds`,
/// `frame`, a shadow or a filter, so every frame is compositor work.
///
/// The closest existing analogue in the repo is the canvas's fit-all overview,
/// `Packages/macOS/CmuxCanvasUI/Sources/CmuxCanvasUI/CanvasRootView+Viewport.swift:251`
/// (`toggleOverview()`), and its cancel path at `:224`
/// (`cancelDiscreteZoomAnimation()`). Two things are reused from it: the
/// generation counter that stops a stale completion block from tearing down a
/// transition that has already been retargeted, and the
/// `CATransaction.setCompletionBlock` plus `Task { @MainActor ... }` hop, which
/// is this repo's convention for getting back onto the main actor from a Core
/// Animation callback. What is *not* reused is its mechanism: `toggleOverview`
/// animates one scroll view's `magnification` to fit everything, which is a
/// camera move. Row 77 needs each card's own rect to interpolate, which a
/// single camera transform cannot express once the cards change their relative
/// spacing — the carousel's pitch is 0.739 W and the grid's column pitch is
/// 0.305 W.
@MainActor
final class CarouselGridPresenter {
    enum Mode: Equatable {
        case carousel
        case grid
    }

    /// One card the presenter drives. `layer` belongs to U1; this type only
    /// ever writes its `position` and `transform`, and never reparents it, so a
    /// live terminal surface is not detached by a mode toggle.
    struct Card {
        let layer: CALayer
        /// The card's rest rect in the carousel, in the contract's top-left
        /// viewport coordinates. A flank's rect is already the 0.94-scaled one.
        var carouselRect: CGRect

        init(layer: CALayer, carouselRect: CGRect) {
            self.layer = layer
            self.carouselRect = carouselRect
        }
    }

    private static let positionKey = "carousel.grid.position"
    private static let transformKey = "carousel.grid.transform"
    private static let fadeKey = "carousel.grid.fade"

    private(set) var mode: Mode = .carousel
    private(set) var selectedSlot: Int = 0
    private(set) var isTransitioning = false

    /// Fired when grid mode is left, carrying the slot the ring was on, so the
    /// carousel can centre it. VIDEO-REVIEW section 2.7 proves the reference's
    /// grid is selectable — entering on Slack and leaving with Lovable centred
    /// — while never showing how; row 80 gives it a visible mechanism.
    var onSelectionCommitted: ((Int) -> Void)?

    private(set) var geometry: CarouselOverlayGeometry
    private(set) var layout: CarouselGridLayout
    private var cards: [Card] = []
    private let indicator: CarouselGridSelectionIndicator
    private weak var host: CarouselOverlayHostView?
    private var generation: UInt64 = 0

    /// `indicator` is optional rather than defaulted because a default
    /// argument expression is evaluated in a nonisolated context, and building
    /// a `CALayer`-owning type there is a main-actor violation the compiler
    /// rejects outright. Constructing it inside the initializer body, which is
    /// isolated, is the fix.
    init(geometry: CarouselOverlayGeometry,
         host: CarouselOverlayHostView?,
         indicator: CarouselGridSelectionIndicator? = nil) {
        self.geometry = geometry
        self.layout = CarouselGridLayout(geometry: geometry)
        self.host = host
        self.indicator = indicator ?? CarouselGridSelectionIndicator()
    }

    var selectionIndicator: CarouselGridSelectionIndicator { indicator }

    // MARK: - Input

    func setCards(_ cards: [Card]) {
        self.cards = cards
        layout = CarouselGridLayout(geometry: geometry, count: max(cards.count, 1))
        if selectedSlot >= cards.count { selectedSlot = max(0, cards.count - 1) }
        if mode == .grid { applyTargets(animated: false) }
    }

    func setGeometry(_ geometry: CarouselOverlayGeometry) {
        self.geometry = geometry
        layout = CarouselGridLayout(geometry: geometry, count: max(cards.count, 1))
        indicator.configure(geometry: geometry, gridCardWidth: layout.cardSize.width)
        if mode == .grid { applyTargets(animated: false) }
    }

    func setSelectedSlot(_ slot: Int) {
        guard !cards.isEmpty else { return }
        selectedSlot = min(max(slot, 0), cards.count - 1)
        if mode == .grid { moveIndicator(animated: false) }
    }

    // MARK: - Mode

    /// The entry point the grid chord drives. `Sources/KeyboardShortcutSettings.swift`
    /// is U1's file and is not edited here; MAKER-U6.md carries the exact case
    /// U1 adds to route Ctrl-Cmd-M to this method. Ctrl-Cmd-M was re-confirmed
    /// free at the branch-cut sha 57460cc83f, and Ctrl-Cmd-G re-confirmed taken
    /// by `.newWorkspaceGroup` at `KeyboardShortcutSettings.swift:490`, which is
    /// the check ruling D-15 requires be repeated rather than inherited.
    func toggle() {
        setMode(mode == .grid ? .carousel : .grid, animated: true)
    }

    func setMode(_ newMode: Mode, animated: Bool) {
        guard newMode != mode else { return }
        let leavingGrid = mode == .grid && newMode == .carousel
        mode = newMode

        if newMode == .grid {
            indicator.configure(geometry: geometry, gridCardWidth: layout.cardSize.width)
            if let host, let hostLayer = host.overlayLayer {
                indicator.attach(to: hostLayer)
            }
            moveIndicator(animated: false)
        }

        applyTargets(animated: animated)

        let fadeDuration = CarouselOverlayMotion.reduceMotion
            ? CarouselOverlayMotion.reducedCrossFadeHalf
            : CarouselOverlayMotion.gridTransition
        indicator.setVisible(newMode == .grid, animated: animated, duration: fadeDuration)

        if leavingGrid {
            onSelectionCommitted?(selectedSlot)
        }
    }

    /// CONTRACT row 80's second half: the indicator follows navigation within
    /// the grid. Wraps, matching the carousel's own wrap at row 51 so the two
    /// readings never disagree at the ends.
    func moveSelection(by delta: Int) {
        guard mode == .grid, !cards.isEmpty else { return }
        let count = cards.count
        selectedSlot = ((selectedSlot + delta) % count + count) % count
        moveIndicator(animated: true)
    }

    func moveSelectionByRow(_ delta: Int) {
        guard mode == .grid, !cards.isEmpty else { return }
        moveSelection(by: delta * CarouselGridLayout.columns)
    }

    // MARK: - Geometry

    func targetRect(forSlot index: Int) -> CGRect {
        switch mode {
        case .grid:
            return layout.rect(forSlot: index)
        case .carousel:
            guard index < cards.count else { return .zero }
            return cards[index].carouselRect
        }
    }

    // MARK: - Transition

    private func applyTargets(animated: Bool) {
        guard !cards.isEmpty else { return }
        generation &+= 1
        let currentGeneration = generation

        guard animated else {
            snapToTargets()
            isTransitioning = false
            return
        }

        if CarouselOverlayMotion.reduceMotion {
            runReducedMotionCrossFade(generation: currentGeneration)
            return
        }

        isTransitioning = true
        let duration = CarouselOverlayMotion.gridTransition
        let timing = CarouselOverlayMotion.easeInOut

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishTransition(generation: currentGeneration)
            }
        }

        for (index, card) in cards.enumerated() {
            guard let parent = card.layer.superlayer else { continue }
            let presentation = card.layer.presentation()
            let fromPosition = presentation?.position ?? card.layer.position
            let fromTransform = presentation?.transform ?? card.layer.transform

            let (toPosition, toScale) = resolvedTarget(for: card, slot: index, in: parent)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.layer.position = toPosition
            card.layer.transform = CATransform3DMakeScale(toScale, toScale, 1)
            CATransaction.commit()

            // Retargeting from the presentation value, not from the last
            // target, is what makes a second chord mid-flight reverse
            // continuously instead of jumping — Apple's Designing Fluid
            // Interfaces, section 3, and the reason a CSS-keyframe-shaped
            // animation is wrong here.
            //
            // minimal: retargets from the presentation *value*, not from its
            // velocity, so a reversal has a velocity discontinuity of at most
            // one frame. A CASpringAnimation carrying initialVelocity is the
            // upgrade, and is only worth it if a gesture ever drives the grid.
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSValue(point: fromPosition)
            position.duration = duration
            position.timingFunction = timing
            card.layer.add(position, forKey: Self.positionKey)

            let transform = CABasicAnimation(keyPath: "transform")
            transform.fromValue = NSValue(caTransform3D: fromTransform)
            transform.duration = duration
            transform.timingFunction = timing
            card.layer.add(transform, forKey: Self.transformKey)
        }

        CATransaction.commit()
    }

    /// CONTRACT row 113: under reduced motion every animation degrades to a
    /// cross-fade with zero translation and zero scale change. The cards do end
    /// up somewhere else, so the honest form of "zero translation" is that
    /// **no card moves or scales in any frame where it is visible**: opacity
    /// runs to zero, geometry snaps while opacity is exactly zero, opacity runs
    /// back. That is the property the test asserts, frame by frame.
    private func runReducedMotionCrossFade(generation currentGeneration: UInt64) {
        isTransitioning = true
        let half = CarouselOverlayMotion.reducedCrossFadeHalf

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.completeReducedMotionCrossFade(generation: currentGeneration, half: half)
            }
        }
        for card in cards {
            let from = card.layer.presentation()?.opacity ?? card.layer.opacity
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.layer.opacity = 0
            CATransaction.commit()

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = from
            fade.duration = half
            fade.timingFunction = CarouselOverlayMotion.easeOut
            card.layer.add(fade, forKey: Self.fadeKey)
        }
        CATransaction.commit()
    }

    private func completeReducedMotionCrossFade(generation currentGeneration: UInt64, half: CFTimeInterval) {
        guard currentGeneration == generation else { return }
        snapToTargets()

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor [weak self] in
                self?.finishTransition(generation: currentGeneration)
            }
        }
        for card in cards {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            card.layer.opacity = 1
            CATransaction.commit()

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.duration = half
            fade.timingFunction = CarouselOverlayMotion.easeOut
            card.layer.add(fade, forKey: Self.fadeKey)
        }
        CATransaction.commit()
    }

    private func snapToTargets() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, card) in cards.enumerated() {
            guard let parent = card.layer.superlayer else { continue }
            let (position, scale) = resolvedTarget(for: card, slot: index, in: parent)
            card.layer.removeAnimation(forKey: Self.positionKey)
            card.layer.removeAnimation(forKey: Self.transformKey)
            card.layer.position = position
            card.layer.transform = CATransform3DMakeScale(scale, scale, 1)
        }
        CATransaction.commit()
        moveIndicator(animated: false)
    }

    /// Maps a card's target rect, stated in viewport coordinates, onto the
    /// `position` and uniform scale its own superlayer needs — so the card can
    /// live inside U1's track with whatever transform the track carries, and
    /// this code does not need to know about it. `CALayer.convert` does the
    /// work. The anchor point is read rather than assumed, because a card whose
    /// anchor is not the centre would otherwise land half a card off.
    private func resolvedTarget(for card: Card, slot: Int, in parent: CALayer) -> (position: CGPoint, scale: CGFloat) {
        let target = targetRect(forSlot: slot)
        let width = card.layer.bounds.width
        let scale = width > 0 ? target.width / width : 1
        let anchor = card.layer.anchorPoint
        let anchorInViewport = CGPoint(
            x: target.minX + anchor.x * target.width,
            y: target.minY + anchor.y * target.height
        )
        let inHostLayer = host?.viewportToLayer(anchorInViewport) ?? anchorInViewport
        let position: CGPoint
        if let hostLayer = host?.overlayLayer, hostLayer !== parent {
            position = hostLayer.convert(inHostLayer, to: parent)
        } else {
            position = inHostLayer
        }
        return (position, scale)
    }

    private func moveIndicator(animated: Bool) {
        guard mode == .grid, !cards.isEmpty else { return }
        let cardRect = layout.rect(forSlot: min(selectedSlot, cards.count - 1))
        let ring = indicator.ringFrame(around: cardRect, geometry: geometry)
        indicator.move(to: host?.viewportToLayer(ring) ?? ring, animated: animated)
    }

    private func finishTransition(generation currentGeneration: UInt64) {
        guard currentGeneration == generation else { return }
        isTransitioning = false
        // CONTRACT row 83 (X7): nothing an overlay drew may outlive its close.
        // The reference leaves a wireframe afterimage of its closing modal
        // visible for about 3.5 s (VIDEO-REVIEW section 2.8); the shape of that
        // bug is a completion block that ran for a superseded generation, which
        // is why the guard above comes first and the teardown second.
        if mode == .carousel {
            indicator.detach()
            for card in cards {
                card.layer.removeAnimation(forKey: Self.positionKey)
                card.layer.removeAnimation(forKey: Self.transformKey)
                card.layer.removeAnimation(forKey: Self.fadeKey)
            }
        }
    }

    /// Test and teardown seam: proves nothing the grid drew is still in the
    /// layer tree, which is row 83's assertion rather than an eyeball.
    var residualOverlayLayerCount: Int {
        guard let hostLayer = host?.overlayLayer else { return 0 }
        return (hostLayer.sublayers ?? []).filter { ($0.name ?? "").hasPrefix("carousel.grid") }.count
    }
}
