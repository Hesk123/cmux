// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Who owns keyboard focus in carousel mode.
///
/// Ruling D-1: the prompt bar owns focus by default; clicking a card hands
/// first responder to that card's terminal; Esc returns it to the prompt bar.
/// There is no third state — in particular there is no "empty field" state,
/// because ruling D-15a removed emptiness as an input mode.
enum CarouselFocusOwner: Equatable, Sendable {
    /// Default on entering carousel mode. Keystrokes edit the composed line.
    case promptBar
    /// Entered by clicking the centred card. Every key, arrows included, goes
    /// to that card's pty.
    case centredTerminal
}
