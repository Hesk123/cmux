import Foundation

// MARK: - Frozen cross-unit interface
//
// These three declarations are the implementation plan's frozen interface
// ("Publishes to other units", § 6, U1). U1 owns them; U5 landed this file
// because U5 shipped first and U3, U4 and U5 all consume it. **Merge note for
// the integrator: if U1 also lands these declarations, keep exactly one copy —
// both are transcriptions of the same frozen block.**

/// The value every unit shares to describe one carousel card.
struct CarouselSession: Equatable, Identifiable, Sendable {
    let panelId: UUID
    /// The workspace the panel belongs to (row 132). Optional: construction
    /// sites that genuinely do not know it (fixtures, compat shapes) pass
    /// nil rather than a fabricated UUID, which would break panel lookup and
    /// value semantics. Owned by U1; this copy deletes at integration.
    let workspaceId: UUID?
    /// `SurfaceResourceID.description`
    let resourceId: String
    /// `nil` when the surface is not a Claude Code session.
    let claudeSessionId: String?
    let projectSlug: String?
    let displayName: String
    let subtitle: String

    var id: UUID { panelId }

    init(
        panelId: UUID,
        workspaceId: UUID? = nil,
        resourceId: String,
        claudeSessionId: String?,
        projectSlug: String?,
        displayName: String,
        subtitle: String
    ) {
        self.panelId = panelId
        self.workspaceId = workspaceId
        self.resourceId = resourceId
        self.claudeSessionId = claudeSessionId
        self.projectSlug = projectSlug
        self.displayName = displayName
        self.subtitle = subtitle
    }
}

/// Consumed by U3, U4 and U5. Row 125 — the top bar follows the centred card
/// through this protocol and nothing else.
@MainActor
protocol CarouselSessionRouting: AnyObject {
    var centredSession: CarouselSession? { get }
    var onCentredSessionChanged: ((CarouselSession?) -> Void)? { get set }
}
