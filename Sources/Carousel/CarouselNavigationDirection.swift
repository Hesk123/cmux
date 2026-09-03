// Modified 2026-09-03 for the cmux carousel build (unit U3).
// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Which way a carousel navigation gesture moves the centred card.
///
/// CONTRACT rows 5 and 114. The only two gestures that produce one of these are
/// the ⌃⌘←/⌃⌘→ chords and the two-finger horizontal trackpad swipe. Per ruling
/// D-15a a bare arrow key never produces one, in any focus state.
///
/// DELETE THIS FILE AT INTEGRATION. The orchestrator ruled U1's declaration
/// canonical, because U1's carries `slotStep` — the signed track step, which is
/// a geometry decision and belongs with the track. This copy exists only so
/// `carousel/u3` compiles and its tests can execute before U1's branch lands;
/// without it the branch is untestable and row 134 can never be met for U3.
/// U1 has been told to keep theirs. When the branches meet, delete this file
/// and its four `project.pbxproj` entries; nothing else changes, because the
/// two declarations are identical in name, cases and conformances.
enum CarouselNavigationDirection: Equatable, Sendable {
    /// Toward the card currently sitting in the left flank.
    case previous
    /// Toward the card currently sitting in the right flank.
    case next
}
