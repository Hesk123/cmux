// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import Foundation

/// Which session is centred, and a hook for when that changes. U3 rebinds the
/// prompt bar's submit target from this, U4 points its sub-agent watcher at it, and
/// U5 reads the statusline snapshot for it. Frozen alongside
/// ``CarouselGeometryProviding``.
@MainActor
protocol CarouselSessionRouting: AnyObject {
    /// Nil only in row 116's `N = 0` empty state.
    var centredSession: CarouselSession? { get }

    /// Every session the carousel knows about, in row 51's stable order.
    var sessions: [CarouselSession] { get }

    /// Fires on settle, not on keypress. A consumer that rebinds a pty target must
    /// not act on a card that is still travelling.
    var onCentredSessionChanged: ((CarouselSession?) -> Void)? { get set }

    /// Rows 5 and 51. Moves one slot and wraps. `direction` is the user's, so
    /// `.next` moves the track left and brings the right-hand flank to centre.
    func navigate(_ direction: CarouselNavigationDirection)
}

/// Row 5. Named rather than a `Bool` so a call site reads as the gesture it came
/// from. U3 defines the same concept for its key router; if both branches carry a
/// declaration the integrator keeps this one, since geometry is where the sign of
/// the translation is decided.
enum CarouselNavigationDirection: Equatable, Sendable {
    case previous
    case next

    /// The signed slot step. `next` centres the card currently to the right, which
    /// means the track travels one pitch to the **left**.
    var slotStep: Int {
        switch self {
        case .previous: -1
        case .next: 1
        }
    }
}
