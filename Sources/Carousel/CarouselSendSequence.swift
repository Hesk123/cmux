// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Timings for the send and voice/send morph, CONTRACT row 65 (input half) and
/// VIDEO-REVIEW §2.4 / §2.5.
///
/// U2 owns the terminal-side halves of row 65 — the echo, the auto-scroll and
/// the signal-chip dim. U3 owns the input side: when the field clears and how
/// the button glyph crosses over. Both halves are asserted against the same
/// `sendWindow`, which is why it lives here rather than being duplicated.
enum CarouselSendSequence {
    /// Row 65: the three terminal-side effects each land within this of Return.
    static let sendWindow: Duration = .milliseconds(165)
    /// Row 65's stated tolerance.
    static let sendWindowTolerance: Duration = .milliseconds(25)

    /// The panel measured at 60 Hz (ruling D-6 — no ProMotion on this Mac).
    static let frameDuration: Duration = .nanoseconds(16_666_667)

    /// VIDEO-REVIEW §2.5: "one frame later (6.05 s) the input clears". Not a
    /// rounded 16 ms constant — it is one frame of whatever the panel runs at.
    static var inputClearDelay: Duration { frameDuration }

    /// VIDEO-REVIEW §2.4: 3.233 → 3.350 s ≈ 117 ms, decelerating. An icon
    /// crossfade only: the circle never changes size, colour or position.
    static let buttonMorphDuration: Duration = .milliseconds(120)

    /// §2.4: the glyph reverts to the waveform ~120 ms after the send.
    static let buttonRevertDelay: Duration = .milliseconds(120)

    /// True when an observed effect latency satisfies row 65's window.
    static func isWithinSendWindow(_ latency: Duration) -> Bool {
        latency >= sendWindow - sendWindowTolerance
            && latency <= sendWindow + sendWindowTolerance
    }
}
