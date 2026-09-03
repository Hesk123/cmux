// Modified 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 37, 80, 83.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit

/// Hosts the two overlay surfaces U6 owns — the grid selection ring and the
/// toast — above the carousel track, and converts the contract's top-left
/// viewport coordinates into layer coordinates.
///
/// It does **not** host the cards. Those are U1's, and the grid transition
/// drives them where they already live rather than reparenting them, so a live
/// terminal is never detached and re-attached by a mode toggle.
///
/// The flip is done explicitly instead of relying on `isFlipped` propagating to
/// the backing layer, because the whole overlay's correctness rests on it and a
/// silent AppKit change would move every rect by the viewport height with no
/// compile error. `viewportToLayer(_:)` is asserted directly by the tests.
@MainActor
final class CarouselOverlayHostView: NSView {
    static let accessibilityIdentifierValue = "carousel.overlay.host"

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityIdentifier(Self.accessibilityIdentifierValue)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselOverlayHostView is created in code only")
    }

    /// Overlay chrome must never swallow a click meant for a card or the
    /// terminal underneath. Subviews that genuinely want clicks (the toast)
    /// still receive them, because `hitTest` on a subview is consulted first.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// The layer the grid transition and the ring live in. Cards supplied by U1
    /// may sit in any sublayer of this one; conversion goes through
    /// `CALayer.convert` so the track's own transform is accounted for.
    var overlayLayer: CALayer? { layer }

    /// Converts a rect in the contract's top-left viewport coordinates into
    /// this view's backing-layer coordinates.
    /// Reads the backing layer's own flag rather than the view's `isFlipped`,
    /// because it is the layer flag that governs where a manually added
    /// sublayer lands. AppKit sets it for a flipped layer-backed view, and the
    /// tests assert a real sublayer's window-space position rather than trust
    /// that, so this stays honest if the AppKit behaviour ever changes.
    func viewportToLayer(_ rect: CGRect) -> CGRect {
        guard let layer, !layer.isGeometryFlipped else { return rect }
        return CGRect(
            x: rect.minX,
            y: layer.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func viewportToLayer(_ point: CGPoint) -> CGPoint {
        guard let layer, !layer.isGeometryFlipped else { return point }
        return CGPoint(x: point.x, y: layer.bounds.height - point.y)
    }
}
