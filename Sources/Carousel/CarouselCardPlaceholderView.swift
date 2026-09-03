// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import SwiftUI

/// What a flank shows before its surface has ever been captured (CONTRACT row 10,
/// team-lead ruling of 2026-09-02).
///
/// Only the centred session has a live libghostty view, and Ghostty pauses a
/// surface that is not visible (`GhosttyTerminalView.swift:4015-4017`), so a session
/// this app run has never centred has no pixels to snapshot. The ruling is that such
/// a card renders **this** - the session's own name, working directory and last
/// activity, in the same card chrome - and takes its first real capture when it
/// first becomes the centre. Not a black rectangle, and not a pre-warm that would
/// contradict row 115's "exactly one live view at rest".
///
/// Everything here is real: the name and cwd come from the surface, the timestamp
/// from the Hive mirror. Row 85 forbids a stand-in, and this is not one - it is an
/// honest statement of what is known about a session that has not been opened yet.
struct CarouselCardPlaceholderView: View {
    let session: CarouselSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Spacer(minLength: 0)
            Text(session.displayName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
            Text(session.subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Text(lastActivityText)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.38))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(CarouselAccessibility.cardPlaceholder)
        .accessibilityLabel(session.displayName)
        // The floor again: without this the placeholder is indistinguishable from a
        // rendered terminal to anyone not looking at it.
        .accessibilityValue(Text(lastActivityText))
        .accessibilityHint(Text(String(
            localized: "carousel.placeholder.hint",
            defaultValue: "Not yet rendered. Centre this card to load it."
        )))
    }

    var lastActivityText: String {
        guard let lastActivity = session.lastActivity else {
            // "Unknown" and "a long time ago" are different facts and are rendered
            // as different strings. A live Hive session was observed with an
            // `updatedAt` 6.7 days old and a running pid, so neither implies dead.
            return String(
                localized: "carousel.placeholder.noActivity",
                defaultValue: "Not opened in this window yet"
            )
        }
        return String(
            localized: "carousel.placeholder.lastActivity",
            defaultValue: "Last activity \(lastActivity.formatted(.relative(presentation: .named)))"
        )
    }
}
