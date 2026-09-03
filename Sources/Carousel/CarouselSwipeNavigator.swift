// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit

/// Two-finger horizontal trackpad swipe, the second navigation gesture in
/// rulings D-1 and D-15 (CONTRACT row 5).
///
/// Phase-tracked so one physical gesture advances the carousel exactly one
/// pitch however far the fingers travel — without that, a single flick fires a
/// switch on every scroll event and the track runs away. Dominant-axis
/// selection mirrors the house pattern in `CanvasPaneView.scrollWheel`
/// (Packages/macOS/CmuxCanvasUI/.../CanvasPaneView.swift:164-172).
@MainActor
final class CarouselSwipeNavigator {
    /// Horizontal travel, in points, before a gesture commits to one pitch.
    /// Below this a swipe reads as an accidental brush against the trackpad.
    static let commitThreshold: Double = 24

    /// A gesture is dominated by its horizontal axis only past this ratio, so a
    /// mostly-vertical scroll over a card never switches session.
    static let horizontalDominanceRatio: Double = 1.2

    private var accumulatedX: Double = 0
    private var accumulatedY: Double = 0
    private var didCommitThisGesture = false

    /// Feeds one `.scrollWheel` event. Returns a direction on the single event
    /// that commits the gesture, and `nil` on every other event.
    func consume(
        scrollingDeltaX: Double,
        scrollingDeltaY: Double,
        phase: NSEvent.Phase,
        momentumPhase: NSEvent.Phase
    ) -> CarouselNavigationDirection? {
        if phase.contains(.began) {
            reset()
        }

        // Momentum is the trackpad coasting after the fingers lift. Honouring it
        // would turn one flick into a burst of switches.
        guard momentumPhase.isEmpty else {
            if phase.contains(.ended) || phase.contains(.cancelled) { reset() }
            return nil
        }

        accumulatedX += scrollingDeltaX
        accumulatedY += scrollingDeltaY

        defer {
            if phase.contains(.ended) || phase.contains(.cancelled) { reset() }
        }

        guard !didCommitThisGesture else { return nil }
        guard abs(accumulatedX) >= Self.commitThreshold else { return nil }
        guard abs(accumulatedX) >= abs(accumulatedY) * Self.horizontalDominanceRatio else {
            return nil
        }

        didCommitThisGesture = true
        // A trackpad's natural-scroll deltaX is positive when content moves
        // right, i.e. when the user reaches toward the previous card.
        return accumulatedX > 0 ? .previous : .next
    }

    func reset() {
        accumulatedX = 0
        accumulatedY = 0
        didCommitThisGesture = false
    }
}
