// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import SwiftUI

/// SwiftUI host for the carousel, modelled on `WorkspaceCanvasHostView`.
///
/// This is the single legacy-observing boundary, exactly as the canvas host is: it
/// watches the `ObservableObject` stores and hands the AppKit side what it needs.
/// Nothing below this point observes a store, which is the rule AGENTS.md states for
/// any view near a terminal surface, and no store read happens inside `body` beyond
/// the two the dependency itself requires.
struct CarouselHostView: View {
    @ObservedObject var tabManager: TabManager
    /// D-9 / row 132: the carousel is scoped to mounted workspaces. An unmounted
    /// workspace's panels have no live view in this window at all, and force-mounting
    /// them to populate the carousel would defeat the background-retention policy
    /// that bounds memory on purpose.
    let mountedWorkspaceIds: [UUID]

    var body: some View {
        CarouselRepresentable(
            workspaces: tabManager.tabs,
            mountedWorkspaceIds: Set(mountedWorkspaceIds),
            panelForSession: panelForSession
        )
    }

    private func panelForSession(_ session: CarouselSession) -> TerminalPanel? {
        // A session with no workspace resolves to no panel rather than to the first
        // workspace, which is what a `nil == nil` match would have given.
        guard let workspaceId = session.workspaceId else { return nil }
        return tabManager.tabs
            .first { $0.id == workspaceId }?
            .panels[session.panelId] as? TerminalPanel
    }
}

/// The one place SwiftUI state flows into the AppKit carousel.
private struct CarouselRepresentable: NSViewRepresentable {
    let workspaces: [Workspace]
    let mountedWorkspaceIds: Set<UUID>
    let panelForSession: (CarouselSession) -> TerminalPanel?

    func makeNSView(context: Context) -> CarouselRootView {
        CarouselRootView(metrics: CarouselMetrics(viewport: CarouselMetrics.referenceViewport))
    }

    func updateNSView(_ nsView: CarouselRootView, context: Context) {
        nsView.update(
            workspaces: workspaces,
            mountedWorkspaceIds: mountedWorkspaceIds,
            panelForSession: panelForSession
        )
    }

    static func dismantleNSView(_ nsView: CarouselRootView, coordinator: ()) {
        // Hands the live terminal back. Without this, leaving carousel mode strands a
        // `GhosttySurfaceScrollView` parented to a dead view, and the split layout
        // rebinds onto a surface it no longer owns.
        nsView.teardown()
    }
}
