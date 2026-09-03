// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Where a key event goes in carousel mode.
///
/// This is the single decision CONTRACT row 114 defines, expressed as a value
/// so it can be asserted without driving the UI. Rows 5, 50 and 61 defer to it.
enum CarouselKeyRouting: Equatable, Sendable {
    /// A navigation chord (⌃⌘← / ⌃⌘→) or a settled swipe.
    case navigateCarousel(CarouselNavigationDirection)
    /// The grid-mode chord (⌃⌘M).
    case toggleGrid
    /// The carousel-mode chord (⌃⌘K).
    case toggleCarouselMode
    /// The key edits the composed line in the prompt bar's text field.
    case promptBarField
    /// The key is written to the centred card's pty.
    case centredPty
    /// Esc pressed while a terminal held focus: hand focus back to the bar.
    case restoreFocusToPromptBar
}
