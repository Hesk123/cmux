// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import Foundation

/// Builds the card list: enumerate surfaces, keep the ones running an agent, cross
/// check liveness against the mirrored data root, and put them in a stable order.
/// CONTRACT rows 51, 85, 105, 116, 124, 126, 132 and D-4, D-9.
///
/// This is the only place the carousel decides what a card *is*. Row 85 forbids mock
/// or seed data anywhere outside the test target, so nothing here invents a session,
/// a name or a count: every field traces to a live cmux surface or to a file in the
/// mirror, and the empty case renders empty.
/// One read of the world. Returned as a value rather than left on the model as
/// mutable properties, because `CarouselHostView` computes it inside `body`:
/// AGENTS.md states that no function called from `body` may write state, and a
/// caller that had to read `isMirrorFresh` *after* calling `sessions()` would be
/// order-dependent on top of that.
struct CarouselSessionSnapshot: Equatable {
    var sessions: [CarouselSession]
    /// Row 132 / D-9. Agent surfaces excluded because their workspace is not
    /// mounted, so their panels have no live view in this window at all. Surfaced
    /// as a count on the sub-agents chip (U4) rather than dropped silently, and
    /// never force-mounted: the background-retention policy bounds memory on purpose.
    var unmountedAgentSurfaceCount: Int
    /// Row 117. True when the mirror is fresh enough for a status pill to make a
    /// claim. False renders the stale treatment, which is a different state from
    /// empty and from stopped.
    var isMirrorFresh: Bool
    var mirrorAge: TimeInterval?
}

@MainActor
final class CarouselSessionModel {
    private let liveness: CarouselSessionLiveness

    init(liveness: CarouselSessionLiveness) {
        self.liveness = liveness
    }

    /// Builds the current card list.
    ///
    /// - Parameters:
    ///   - workspaces: every workspace in the window, in `TabManager` order.
    ///   - mountedWorkspaceIds: the mounted subset. D-9 scopes the carousel to it.
    func snapshot(
        workspaces: [Workspace],
        mountedWorkspaceIds: Set<UUID>,
        now: Date = .now
    ) -> CarouselSessionSnapshot {
        let records = liveness.records(now: now)
        let isMirrorFresh = liveness.isMirrorFresh(now: now)
        let mirrorAge = liveness.mirrorAge(now: now)

        var mounted: [CarouselSession] = []
        var unmountedCount = 0

        for workspace in workspaces {
            let isMounted = mountedWorkspaceIds.contains(workspace.id)
            for panelId in workspace.orderedPanelIds {
                guard let panel = workspace.panels[panelId] as? TerminalPanel else { continue }
                guard Self.isAgentSurface(panel: panel, workspace: workspace) else { continue }
                guard isMounted else {
                    unmountedCount += 1
                    continue
                }
                mounted.append(makeSession(
                    panel: panel,
                    workspace: workspace,
                    records: records,
                    isMirrorFresh: isMirrorFresh,
                    mirrorAge: mirrorAge
                ))
            }
        }

        return CarouselSessionSnapshot(
            // Row 51. Ordering by the resource identity rather than by a saved array
            // makes "identical order across relaunch" a property of the identity, so
            // a reordered sidebar or a rebuilt layout cannot shuffle the carousel.
            sessions: mounted.sorted { $0.resourceId < $1.resourceId },
            unmountedAgentSurfaceCount: unmountedCount,
            isMirrorFresh: isMirrorFresh,
            mirrorAge: mirrorAge
        )
    }

    /// The "running an agent" predicate. Reuses `TextBoxAgentDetection` through the
    /// context builder the text box itself uses, so the carousel's notion of an
    /// agent surface is the same one the rest of the app already holds rather than
    /// a second, divergent definition.
    static func isAgentSurface(panel: TerminalPanel, workspace: Workspace) -> Bool {
        let context = WorkspaceContentView.terminalAgentContext(panel: panel, workspace: workspace)
        return TextBoxAgentDetection.supportsAgentPrefixes(context: context)
    }

    /// Row 124: Claude Code surfaces are in scope; Codex and OpenCode are not, and
    /// none of the `~/.claude` paths exist for them. An out-of-scope surface still
    /// gets a card - it is a running agent - but a defined out-of-scope one that
    /// claims no sub-agent or usage data it cannot read.
    static func isClaudeCodeSurface(panel: TerminalPanel, workspace: Workspace) -> Bool {
        let context = WorkspaceContentView.terminalAgentContext(panel: panel, workspace: workspace)
        return TextBoxAgentDetection.isClaudeCode(context: context)
    }

    private func makeSession(
        panel: TerminalPanel,
        workspace: Workspace,
        records: [CarouselClaudeSessionRecord],
        isMirrorFresh: Bool,
        mirrorAge: TimeInterval?
    ) -> CarouselSession {
        let isClaude = Self.isClaudeCodeSurface(panel: panel, workspace: workspace)
        let identity = Self.identity(panel: panel, workspace: workspace)
        let record = isClaude ? CarouselSessionMatcher.match(surface: identity, against: records) : nil

        let status: CarouselSessionStatus
        if !isClaude {
            status = .outOfScope
        } else if !isMirrorFresh {
            status = .stale(age: mirrorAge ?? CarouselDataRoot.stalenessBound)
        } else if let record {
            status = record.carouselStatus
        } else {
            // Row 126: the surface is open but the mirror has no session for it, so
            // the agent behind it has stopped.
            status = .stopped
        }

        return CarouselSession(
            panelId: panel.id,
            workspaceId: workspace.id,
            resourceId: LocalSurfaceProvider.resourceID(forTerminalPanel: panel.id).description,
            claudeSessionId: record?.sessionId,
            projectSlug: record?.projectSlug,
            displayName: record?.name ?? panel.displayTitle,
            subtitle: workspace.panelDirectories[panel.id] ?? record?.cwd ?? workspace.title,
            status: status,
            isClaudeCodeSurface: isClaude,
            lastActivity: record?.lastActivity
        )
    }

    private static func identity(panel: TerminalPanel, workspace: Workspace) -> CarouselSurfaceIdentity {
        CarouselSurfaceIdentity(
            tmuxPaneId: panel.tmuxLayoutReport?.activePane?.paneId,
            launchCommand: launchCommand(panel: panel, workspace: workspace),
            title: panel.displayTitle,
            directory: workspace.panelDirectories[panel.id]
        )
    }

    private static func launchCommand(panel: TerminalPanel, workspace: Workspace) -> String? {
        // The agent context already concatenates `initialCommand:` and
        // `tmuxStartCommand:`; reusing it keeps one reader of those fields rather
        // than a second that can fall behind.
        let context = WorkspaceContentView.terminalAgentContext(panel: panel, workspace: workspace)
        return context.isEmpty ? nil : context
    }
}
