// Added 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 14, 37, 67, 68, 78.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import Foundation

/// One toast. CONTRACT row 37 fixes its geometry; rows 67, 68 and 78 fix its
/// motion.
///
/// **CONTRACT row 14 (P12), the second terminal-native addition.** Row 14 asks
/// for at least two additions the reference has no vocabulary for, drawn from
/// what cmux already tracks per surface, and names row 47's footer signal chips
/// as the first. This is the second, and it is a change of *source*, not of
/// layout: the reference's four toasts are app notifications — `Notion — Added
/// the Q1 four-headcount…`, `Gmail — Already blocked on your calenda…` — routed
/// from apps the demo does not run. There is no such surface here. A cmux toast
/// instead carries **the tail of a background session's own terminal output**,
/// with the session's name and branch as the title and its live status dot in
/// place of an app-icon tile. It answers the question the carousel cannot,
/// because the session that finished is by definition not the one on screen:
/// which of the other five just did something, and what did it say.
///
/// The body is deliberately the raw last non-empty line rather than a summary.
/// Nothing here invents a field: CONTRACT row 85 forbids mock data, and every
/// value below is either supplied by the caller from a real surface or rendered
/// as a defined empty state.
struct CarouselToast: Equatable, Identifiable {
    enum Status: Equatable {
        case running
        case idle
        case stopped
        /// CONTRACT row 127: a signal past its max age renders as unknown
        /// rather than as idle.
        case unknown

        /// Spoken form for the toast's accessibility label (ruling (d) A3):
        /// VoiceOver must say whether the session is running, not just read
        /// the title and body the dot's colour already codes.
        var accessibilityText: String {
            switch self {
            case .running: return "running"
            case .idle: return "idle"
            case .stopped: return "stopped"
            case .unknown: return "unknown"
            }
        }
    }

    let id: UUID
    /// The session's display name, and its git branch when the surface has one.
    /// CONTRACT row 47 confirms cmux tracks the branch per surface.
    let title: String
    /// The last non-empty line that session's pty produced, truncated with an
    /// ellipsis by the view, never by the model — so a test can assert the full
    /// string reached the toast and the view did the eliding.
    let body: String
    let status: Status
    /// The slot this toast came from, so a click can centre that session.
    let slot: Int?

    init(id: UUID = UUID(), title: String, body: String, status: Status, slot: Int? = nil) {
        self.id = id
        self.title = title
        self.body = body
        self.status = status
        self.slot = slot
    }

    /// The defined empty state for a session that produced no output at all.
    /// CONTRACT row 16's rubric requires every state to have one.
    static func emptyBody(for title: String, status: Status, slot: Int? = nil) -> CarouselToast {
        CarouselToast(title: title, body: "No output yet", status: status, slot: slot)
    }
}
