// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import SwiftUI

/// Row 85 and row 116's `N = 0`. An honest empty state, and a *distinct* stale one.
///
/// The distinction is load-bearing. "No agent surfaces are open" and "the mirror of
/// Hive's `~/.claude` is stale or unreachable, so I cannot tell you" are different
/// facts, and collapsing them would let a downed ssh bridge read as an idle machine.
/// Row 85 asserts the empty state against a genuinely empty root *and* against a host
/// that has a live session but is unreachable, precisely so the two cannot be
/// conflated.
struct CarouselEmptyStateView: View {
    enum Reason: Equatable {
        /// Every workspace was searched and no surface is running an agent.
        case noAgentSurfaces
        /// The mirror is older than `CarouselDataRoot.stalenessBound`.
        case mirrorStale(age: TimeInterval)
        /// Row 132: agent surfaces exist but their workspaces are not mounted.
        case allSurfacesUnmounted(count: Int)
    }

    let reason: Reason

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
        .accessibilityIdentifier(CarouselAccessibility.emptyState)
    }

    private var icon: String {
        switch reason {
        case .noAgentSurfaces: "sparkles"
        case .mirrorStale: "antenna.radiowaves.left.and.right.slash"
        case .allSurfacesUnmounted: "rectangle.stack"
        }
    }

    private var title: String {
        switch reason {
        case .noAgentSurfaces:
            String(localized: "carousel.empty.noSessions.title", defaultValue: "No agent sessions")
        case .mirrorStale:
            String(localized: "carousel.empty.stale.title", defaultValue: "Session data is stale")
        case .allSurfacesUnmounted:
            String(localized: "carousel.empty.unmounted.title", defaultValue: "No mounted agent sessions")
        }
    }

    private var message: String {
        switch reason {
        case .noAgentSurfaces:
            String(
                localized: "carousel.empty.noSessions.message",
                defaultValue: "Start an agent in a terminal surface and it appears here."
            )
        case .mirrorStale(let age):
            String(
                localized: "carousel.empty.stale.message",
                defaultValue: "The session mirror last updated \(Int(age)) seconds ago. Sessions may be running that this window cannot see."
            )
        case .allSurfacesUnmounted(let count):
            String(
                localized: "carousel.empty.unmounted.message",
                defaultValue: "\(count) agent surfaces are in workspaces this window has not mounted. Open one to bring it into the carousel."
            )
        }
    }
}
