// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Which glyph the action button shows (VIDEO-REVIEW §1.4, §2.4).
///
/// This is the one place emptiness legitimately drives behaviour, and it is not
/// the mode ruling D-15a removed. D-15a bans emptiness from selecting where a
/// *keystroke goes*; here it only selects a glyph, the change is visible on the
/// button itself before the key is pressed, and no keystroke changes meaning.
enum CarouselComposeButtonMode: Equatable, Sendable {
    /// Field empty: waveform / voice glyph.
    case voice
    /// Field has text: ↑ send glyph.
    case send

    init(isComposedLineEmpty: Bool) {
        self = isComposedLineEmpty ? .voice : .send
    }
}
