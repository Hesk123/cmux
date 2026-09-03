// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// The frozen interface U1's carousel track must satisfy for U3's prompt bar,
/// session chip and pty routing to work.
///
/// U3 depends on nothing else from U1. Every member is read at the moment of
/// use and never cached: CONTRACT row 6 requires the prompt bar's bound session
/// to equal the centred card's *after every switch*, and a cached surface would
/// keep sending to the session that was centred when the bar was built.
///
/// Per ruling D-2 only the centred card hosts a live libghostty view, so
/// `centredSubmitSurface` is the only surface U3 may ever write to.
@MainActor
protocol CarouselCentreProviding: AnyObject {
    /// Stable identity of the Claude Code session hosted by the centred card,
    /// or `nil` when the carousel is empty (CONTRACT row 116, N = 0).
    var centredSessionId: String? { get }

    /// Label rendered in the prompt bar's session chip (CONTRACT row 35).
    var centredSessionDisplayName: String? { get }

    /// The centred card's live terminal surface — the Return key's destination.
    var centredSubmitSurface: TextBoxSubmitSurfaceControlling? { get }

    /// Number of cards currently in the track. Navigation is a no-op below two
    /// (CONTRACT row 116).
    var carouselSessionCount: Int { get }

    /// Move the track. Implemented by U1; U3 only ever calls it.
    func navigateCarousel(_ direction: CarouselNavigationDirection)
}
