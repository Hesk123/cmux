// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import CoreGraphics
import Foundation

/// The geometry U1 publishes and U2 and U6 consume. Frozen: U3 is already building
/// against it with a stub track, so the shape here is a contract, not a suggestion.
///
/// Every rect is in **CSS space** - origin top-left, `y` down, logical points -
/// matching how CONTRACT rows 17-41 are written. `CarouselTrackView` is the single
/// place that flips into AppKit's bottom-left origin.
@MainActor
protocol CarouselGeometryProviding: AnyObject {
    /// The one place a layout constant exists.
    var metrics: CarouselMetrics { get }

    /// The at-rest rect of the card `index` slots from centre. Negative is left.
    /// Row 25's pitch and row 23's side scale are both folded in.
    func rect(forSlot index: Int) -> CGRect

    /// Row 38's grid slot, reading left-to-right then top-to-bottom.
    func gridRect(forSlot index: Int) -> CGRect

    /// Which session is centred, as an index into the session list. Rows 51 and 57:
    /// this wraps, so it is always in `0..<sessionCount` and never saturates.
    var centredSlotIndex: Int { get }
}

/// The animatable surface U2 drives. U1 ships the static geometry plus a linear
/// placeholder behind ``setTrackOffset(_:animated:)``; U2 replaces the placeholder
/// with row 52's 300 ms ease-out and row 54's recoil without touching layout.
///
/// The two transforms compose per D-14: what a card renders at is `track * card`.
/// ``trackScale`` is row 54's single track-wide recoil, identical for every card in
/// every frame; ``cardScale(forSlot:)`` is row 55's per-card ramp.
@MainActor
protocol CarouselTrackAnimating: AnyObject {
    /// Horizontal displacement of the whole track from its rest position, in
    /// logical points. One slot is ``CarouselMetrics/pitch``.
    var trackOffset: CGFloat { get set }

    /// Row 54's track-level recoil, 1.0 at rest.
    var trackScale: CGFloat { get set }

    /// The **presentation** offset - what is on screen right now, not the last
    /// target. Row 56 forbids queuing a re-target: a new press cancels the running
    /// animation and starts from this value, which is the only way an interrupted
    /// switch has no jump.
    var presentationTrackOffset: CGFloat { get }

    /// Cancels any running animation, leaving the track at its presentation value.
    func cancelTrackAnimation()

    /// Row 55 / D-14. The per-card scale for a card `slot` steps from centre,
    /// composing with ``trackScale``.
    func cardScale(forSlot slot: Int) -> CGFloat
}
