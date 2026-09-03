// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import Foundation

/// One card: a cmux surface running an agent (CONTRACT row 105, Dawid's answer to
/// Q2). This is the value every other unit reads, so it carries identity and
/// display text and nothing else - no view, no panel reference, no store.
struct CarouselSession: Identifiable, Hashable, Sendable {
    /// The `TerminalPanel` this card mirrors. `Identifiable` over this, so a card
    /// keeps its identity across a reorder.
    let panelId: UUID
    /// The workspace the panel belongs to. Row 132: only mounted workspaces
    /// contribute, and this is what that filter is applied against.
    ///
    /// Optional, because the compatibility initialiser below genuinely does not
    /// know it. Filling it with a fresh `UUID()` would have been worse than
    /// admitting the gap: `panelForSession` looks the panel up *by* this id and
    /// would find nothing, and two otherwise-identical sessions would compare
    /// unequal and hash differently.
    let workspaceId: UUID?
    /// `SurfaceResourceID.description`, i.e. `machine/kind/key`. Row 51 wants a
    /// stable order across relaunch; ordering by this makes stability a property of
    /// the identity rather than of a saved array that can drift.
    let resourceId: String
    /// Nil when the surface is not a Claude Code surface. Row 124 scopes this build
    /// to Claude Code; a Codex or OpenCode surface renders the out-of-scope state
    /// rather than a broken card, and this being nil is how it is recognised.
    let claudeSessionId: String?
    /// The cwd with `/` replaced by `-`, matching Claude Code's own transcript
    /// directory naming. Nil for the same reason as `claudeSessionId`.
    let projectSlug: String?
    /// Row 42's first header line.
    let displayName: String
    /// Row 42's dimmed second line.
    let subtitle: String
    /// Row 43's status, from real session state. Never a constant.
    let status: CarouselSessionStatus
    /// Row 124. False for a Codex / OpenCode / plain-shell agent surface, which
    /// gets a defined out-of-scope card instead of one claiming data it cannot read.
    let isClaudeCodeSurface: Bool
    /// When the mirror last saw this session do anything. Nil when unknown, which
    /// is a different statement from "a long time ago" and is rendered as one.
    /// Read by the row-10 placeholder card, which is all a never-visited flank has.
    let lastActivity: Date?

    var id: UUID { panelId }

    /// Compatibility shape for U5's transcription of the frozen block, so their
    /// construction sites compile against the canonical type without an edit.
    /// The four fields U5's version lacks take their honest unknown values:
    /// no workspace, no session state, no last activity, and not known to be
    /// Claude Code. None of them is guessed into something that reads as a claim.
    init(
        panelId: UUID,
        resourceId: String,
        claudeSessionId: String?,
        projectSlug: String?,
        displayName: String,
        subtitle: String
    ) {
        self.init(
            panelId: panelId,
            workspaceId: nil,
            resourceId: resourceId,
            claudeSessionId: claudeSessionId,
            projectSlug: projectSlug,
            displayName: displayName,
            subtitle: subtitle,
            status: .outOfScope,
            isClaudeCodeSurface: false,
            lastActivity: nil
        )
    }

    init(
        panelId: UUID,
        workspaceId: UUID?,
        resourceId: String,
        claudeSessionId: String?,
        projectSlug: String?,
        displayName: String,
        subtitle: String,
        status: CarouselSessionStatus,
        isClaudeCodeSurface: Bool,
        lastActivity: Date?
    ) {
        self.panelId = panelId
        self.workspaceId = workspaceId
        self.resourceId = resourceId
        self.claudeSessionId = claudeSessionId
        self.projectSlug = projectSlug
        self.displayName = displayName
        self.subtitle = subtitle
        self.status = status
        self.isClaudeCodeSurface = isClaudeCodeSurface
        self.lastActivity = lastActivity
    }
}

/// Row 43 and row 126. What the card's status pill says, derived from the mirrored
/// data root rather than chosen by the view.
enum CarouselSessionStatus: Equatable, Hashable, Sendable {
    /// The session file says the agent is working.
    case busy
    /// The session file exists and the agent is waiting on input.
    case idle
    /// Row 126: the surface is still open but its session file is gone, so the
    /// agent behind it has stopped. Distinct from `unknown`.
    case stopped
    /// Row 117 / D-4: the mirror is stale or unreachable, so no honest claim can be
    /// made about this session. Deliberately not folded into `stopped` - a carousel
    /// that shows a five-minute-old session as live is worse than one that says it
    /// does not know.
    case stale(age: TimeInterval)
    /// Row 124: not a Claude Code surface, so none of the above is readable.
    case outOfScope
}
