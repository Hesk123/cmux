// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import QuartzCore

/// The three-up track: card layout at slot pitch, wrap-around, and the two
/// composing transforms row 54 and row 55 need. CONTRACT rows 20-27, 31, 51, 52,
/// 54, 55, 56, 57, 116.
///
/// **Not an `NSScrollView`.** An earlier revision of the plan drove the track with
/// clip-view bounds because live terminals rode it and a layer transform would have
/// desynced their portal-assigned frames. D-2 removed the live views from the moving
/// track entirely - during a switch all three cards are snapshots - so a plain
/// `CALayer` transform is now the correct engine rather than a hazard, and the Phase
/// 0 spike measured it at 0 dropped frames in 239 intervals.
///
/// Flipped, so `CarouselMetrics`' CSS-space rects are used verbatim.
@MainActor
final class CarouselTrackView: NSView, CarouselGeometryProviding, CarouselTrackAnimating {
    /// Carries both transforms. Cards are its subviews, so one scale on this layer
    /// gives every visible card the same value in every frame - which is what row 54
    /// asserts, by construction rather than by keeping N cards in step.
    private let trackContainer = NSView()

    private var cardsBySlot: [Int: CarouselCardView] = [:]
    private var recycledCards: [CarouselCardView] = []

    private(set) var metrics: CarouselMetrics
    private(set) var sessions: [CarouselSession] = []
    private(set) var centredSlotIndex = 0

    /// Called on settle, never on keypress: a consumer that rebinds a pty target
    /// must not act on a card still travelling.
    var onCentredSessionChanged: ((CarouselSession?) -> Void)?
    /// Fired when the set of laid-out cards changes, so the root can re-mount the
    /// live terminal and refresh snapshots without polling.
    var onCardsChanged: (() -> Void)?

    override var isFlipped: Bool { true }

    init(metrics: CarouselMetrics) {
        self.metrics = metrics
        super.init(frame: .zero)
        wantsLayer = true
        trackContainer.wantsLayer = true
        // Deterministic rather than inherited: the transform maths below assumes the
        // layer's y runs the same way the flipped view's does.
        trackContainer.layer?.isGeometryFlipped = true
        addSubview(trackContainer)
        setAccessibilityIdentifier(CarouselAccessibility.track)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel(String(
            localized: "carousel.track.accessibilityLabel",
            defaultValue: "Agent sessions"
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselTrackView is created in code only")
    }

    // MARK: - CarouselTrackAnimating

    var trackOffset: CGFloat = 0 {
        didSet { applyTrackTransform() }
    }

    var trackScale: CGFloat = 1 {
        didSet { applyTrackTransform() }
    }

    /// Row 56. The value actually on screen this instant, read from the render
    /// server's presentation layer rather than from the model. A re-target that
    /// starts from the last *target* jumps; one that starts from here does not.
    var presentationTrackOffset: CGFloat {
        guard let presentation = trackContainer.layer?.presentation() else { return trackOffset }
        return presentation.transform.m41
    }

    func cancelTrackAnimation() {
        guard let layer = trackContainer.layer else { return }
        let live = presentationTrackOffset
        layer.removeAllAnimations()
        trackOffset = live
    }

    /// Row 55 / D-14. The centre card renders at 1.0 and every other card at 0.94;
    /// during a switch U2 ramps the entering and leaving cards between the two. The
    /// rendered scale of any card is this times ``trackScale``, which is what
    /// removes the 6 % instantaneous pop while keeping row 54's single track value.
    func cardScale(forSlot slot: Int) -> CGFloat {
        slot == 0 ? 1 : CarouselMetrics.sideScale
    }

    private func applyTrackTransform() {
        guard let layer = trackContainer.layer else { return }
        // Scale is anchored at the layer's centre, which is the viewport centre, not
        // the card row's centre 20 CSS above it. At the row-54 peak of 0.971 that
        // difference moves the card by 0.58 CSS px for 65 ms - below row 20's +/-2 px
        // tolerance by more than three times - so the exact-anchor correction is not
        // written. Stated because it is a deliberate simplification, not an oversight.
        // minimal: centre-anchored recoil, exact card-centre anchor if a row ever
        // measures the recoil's vertical displacement.
        layer.transform = CATransform3DConcat(
            CATransform3DMakeScale(trackScale, trackScale, 1),
            CATransform3DMakeTranslation(trackOffset, 0, 0)
        )
    }

    // MARK: - CarouselGeometryProviding

    /// The *rendered* rect of the card `index` slots from centre, at rest - the side
    /// scale is already folded in, because that is what H1's frame diff measures.
    func rect(forSlot index: Int) -> CGRect {
        metrics.rect(forSlot: index)
    }

    func gridRect(forSlot index: Int) -> CGRect {
        metrics.gridRect(forSlot: index)
    }

    /// Synchronous recentre for U6's grid exit. Moves the model, re-seats every card
    /// at its rest rect, and hands back where they landed - no animation, so U6 can
    /// animate from the grid straight to these rects in one stage instead of racing
    /// a recentre it cannot see.
    @discardableResult
    func recentre(to card: CarouselCardID) -> [CarouselCardID: CGRect]? {
        guard let index = sessions.firstIndex(where: { $0.resourceId == card.resourceId }) else {
            return nil
        }
        centredSlotIndex = index
        trackOffset = 0
        trackScale = 1
        reseat()
        onCentredSessionChanged?(centredSession)

        var rects: [CarouselCardID: CGRect] = [:]
        for (slot, cardView) in cardsBySlot {
            guard let session = cardView.session else { continue }
            rects[CarouselCardID(session)] = metrics.rect(forSlot: slot)
        }
        return rects
    }

    /// Suppresses the track's own position writes for the duration of `body`.
    /// `defer` rather than a trailing reset, so a throwing body cannot leave the
    /// track permanently unable to lay itself out.
    func withTrackAnimationSuppressed<T>(_ body: () throws -> T) rethrows -> T {
        isLayoutSuppressed = true
        defer { isLayoutSuppressed = false }
        return try body()
    }

    /// While true, `reseat()` is a no-op: U6 owns these layers.
    private var isLayoutSuppressed = false

    // MARK: - Content

    func update(sessions: [CarouselSession], metrics: CarouselMetrics) {
        let previousCentre = centredSession
        self.metrics = metrics
        self.sessions = sessions
        if sessions.isEmpty {
            centredSlotIndex = 0
        } else {
            centredSlotIndex = min(centredSlotIndex, sessions.count - 1)
        }
        reseat()
        if centredSession != previousCentre {
            onCentredSessionChanged?(centredSession)
        }
    }

    var centredSession: CarouselSession? {
        guard sessions.indices.contains(centredSlotIndex) else { return nil }
        return sessions[centredSlotIndex]
    }

    /// The card currently at centre, when there is one.
    var centreCard: CarouselCardView? { cardsBySlot[0] }

    /// Every laid-out card, keyed by slot. The root reads this to decide which body
    /// gets the live terminal and which get a snapshot.
    var cards: [Int: CarouselCardView] { cardsBySlot }

    // MARK: - Navigation

    /// Rows 5, 51 and 57. Moves one slot and wraps; there is no edge, so no clamp
    /// and no rubber-band.
    ///
    /// Row 116: at one session this is a no-op that does **not** animate, and at
    /// zero there is nothing to move.
    func navigate(_ direction: CarouselNavigationDirection, animator: ((Int) -> Void)? = nil) {
        guard sessions.count > 1 else { return }
        let incomingSlot = direction.slotStep * 2
        // The card that will become a flank after the move enters from two slots out
        // and must exist before the track starts travelling, or it pops in mid-switch.
        ensureCard(atSlot: incomingSlot)
        if let animator {
            animator(direction.slotStep)
        } else {
            // U2 owns the curve. Until it lands, the move is instantaneous rather
            // than a hand-rolled tween that would have to be deleted: an
            // animation nobody specified is worse than none.
            settle(step: direction.slotStep)
        }
    }

    /// Completes a move: adopts the new centre index, resets the track to rest, and
    /// re-lays every card at its at-rest slot. Called by U2 on animation completion,
    /// and directly by ``navigate(_:animator:)`` when no animator is installed.
    func settle(step: Int) {
        guard !sessions.isEmpty else { return }
        let count = sessions.count
        centredSlotIndex = ((centredSlotIndex + step) % count + count) % count
        trackOffset = 0
        trackScale = 1
        reseat()
        onCentredSessionChanged?(centredSession)
    }

    /// The accessibility floor for the track: which session is centred, exposed as a
    /// value a VoiceOver user and an `AXUIElement` read both resolve. Without it the
    /// only cue to the current session is visual position.
    private func updateAccessibilityValue() {
        setAccessibilityValue(centredSession?.displayName ?? "")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        trackContainer.frame = bounds
        metrics.viewport = bounds.size
        reseat()
    }

    /// Lays out one card per visible slot at its rest rect. Cards are pooled by slot
    /// rather than recreated, so a switch never allocates an `NSHostingView` on the
    /// keypress frame.
    private func reseat() {
        guard !isLayoutSuppressed else { return }
        let slots = CarouselMetrics.visibleSlots(forSessionCount: sessions.count)
        let wanted = Set(slots)

        for (slot, card) in cardsBySlot where !wanted.contains(slot) {
            card.removeFromSuperview()
            cardsBySlot.removeValue(forKey: slot)
            recycledCards.append(card)
        }
        for slot in slots {
            ensureCard(atSlot: slot)
        }
        updateAccessibilityValue()
        onCardsChanged?()
    }

    @discardableResult
    private func ensureCard(atSlot slot: Int) -> CarouselCardView? {
        guard let index = CarouselMetrics.sessionIndex(
            forSlot: slot,
            centre: centredSlotIndex,
            sessionCount: sessions.count
        ) else {
            return nil
        }
        let card = cardsBySlot[slot] ?? {
            let reused = recycledCards.popLast() ?? CarouselCardView(metrics: metrics)
            trackContainer.addSubview(reused)
            cardsBySlot[slot] = reused
            return reused
        }()

        // The frame is always the *full* card box; the 0.94 is a layer transform
        // about the card's own centre. Keeping the frame constant is what lets row
        // 55's ramp be a pure transform, and is why a flank and the centre share a
        // vertical centre to within a pixel (row 23).
        let centre = metrics.cardCentre
        card.frame = CGRect(
            x: centre.x + CGFloat(slot) * metrics.pitch - metrics.cardWidth / 2,
            y: centre.y - metrics.cardHeight / 2,
            width: metrics.cardWidth,
            height: metrics.cardHeight
        )
        let scale = cardScale(forSlot: slot)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        card.layer?.transform = CATransform3DMakeScale(scale, scale, 1)
        CATransaction.commit()

        card.apply(session: sessions[index], metrics: metrics, isCentre: slot == 0)
        return card
    }
}
