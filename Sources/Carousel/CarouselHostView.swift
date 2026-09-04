// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
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
    /// Owned by the SwiftUI shell so prompt bar, arrows and submitter share one centre.
    let centre: CarouselCentreAdapter

    var body: some View {
        CarouselRepresentable(
            workspaces: tabManager.tabs,
            mountedWorkspaceIds: Set(mountedWorkspaceIds),
            panelForSession: panelForSession,
            centre: centre
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

/// The frozen U1/U3 seam made concrete: U3's prompt bar, session chip, submit
/// controller and focus coordinator all read the centre through
/// `CarouselCentreProviding`, and this is the one adapter implementing it
/// against the live `CarouselRootView`. Every member resolves on access and
/// nothing is cached, per the row-6 ruling the submit controller documents.
@MainActor
@Observable
final class CarouselCentreAdapter: CarouselCentreProviding {
    weak var rootView: CarouselRootView?

    /// Bumped on every settle. The adapter holds no session state itself; this
    /// generation counter is what publishes change to SwiftUI readers, since
    /// the Observation framework only fires on tracked-property mutation and
    /// an empty poke function would publish nothing.
    private(set) var generation = 0

    /// Poked by the representable whenever the track settles, so SwiftUI
    /// readers (prompt-bar chip, arrows) re-render on switch. The adapter
    /// itself holds no session state.
    func centreDidChange() {
        generation += 1
    }

    var centredSessionId: String? {
        // Reads generation so SwiftUI tracks this across switches: rootView
        // itself does not change when the centre moves.
        _ = generation
        return rootView?.centredSession?.claudeSessionId
    }

    var centredSessionDisplayName: String? {
        _ = generation
        return rootView?.centredSession?.displayName
    }

    var centredSubmitSurface: TextBoxSubmitSurfaceControlling? {
        _ = generation
        guard let rootView, let session = rootView.centredSession else { return nil }
        guard let panel = rootView.panelForSession(session) else { return nil }
        return panel.surface
    }

    var carouselSessionCount: Int {
        _ = generation
        return rootView?.sessions.count ?? 0
    }

    func navigateCarousel(_ direction: CarouselNavigationDirection) {
        rootView?.navigate(direction)
    }

    // MARK: - Prompt bar submit flow (row 65)

    /// The prompt bar's composed line. Lives here (not in ContentView) so the
    /// send-then-clear sequence in `submitComposedLine()` can mutate it from
    /// MainActor without escaping-closure gymnastics in the view.
    var composedLine = ""

    /// Sends the composed line to the centred pty and clears the field one
    /// frame later (U3's `CarouselSendSequence.inputClearDelay`: clearing
    /// synchronously would beat the terminal echo the row measures against).
    /// Refuses on empty lines and with no centred session — never falls back
    /// to "some" surface, per the row-6 ruling. Clears only if the field still
    /// holds the sent line: keystrokes typed during the delay belong to the
    /// next line, not to this one's cleanup.
    func submitComposedLine(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let controller = CarouselSubmitController(centre: self)
        guard controller.sendText(line) else { return }
        controller.sendNamedKey(TextBoxTerminalKey.returnKey.rawValue)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: CarouselSendSequence.inputClearDelay)
            if self?.composedLine == line {
                self?.composedLine = ""
            }
        }
    }
}

/// The one place SwiftUI state flows into the AppKit carousel.
private struct CarouselRepresentable: NSViewRepresentable {
    let workspaces: [Workspace]
    let mountedWorkspaceIds: Set<UUID>
    let panelForSession: (CarouselSession) -> TerminalPanel?
    let centre: CarouselCentreAdapter

    func makeNSView(context: Context) -> CarouselRootView {
        let root = CarouselRootView(metrics: CarouselMetrics(viewport: CarouselMetrics.referenceViewport))
        centre.rootView = root
        root.onCentredSessionChanged = { [weak centre] _ in
            centre?.centreDidChange()
        }
        return root
    }

    func updateNSView(_ nsView: CarouselRootView, context: Context) {
        centre.rootView = nsView
        nsView.update(
            workspaces: workspaces,
            mountedWorkspaceIds: mountedWorkspaceIds,
            panelForSession: panelForSession
        )
    }

    static func dismantleNSView(_ nsView: CarouselRootView, coordinator: CarouselCentreAdapter) {
        // Hands the live terminal back. Without this, leaving carousel mode strands a
        // `GhosttySurfaceScrollView` parented to a dead view, and the split layout
        // rebinds onto a surface it no longer owns.
        nsView.teardown()
    }

    func makeCoordinator() -> CarouselCentreAdapter { centre }
}
