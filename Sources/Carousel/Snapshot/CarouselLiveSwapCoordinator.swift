// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit

/// The four transitions of D-2's swap protocol, in one place so no unit can
/// implement three of them (CONTRACT row 115, plan section 17.1).
///
/// 1. **At rest.** Centre hosts the live view at scale 1.0, unclipped, untransformed.
///    Flanks are snapshot layers at 0.94. The centre's own snapshot is kept warm at
///    <= 4 Hz so transition 2 never has to capture.
/// 2. **Switch start, on the keypress frame.** The centre's live view is unmounted
///    and its warm snapshot put in its place. **No capture happens on this frame.**
///    The Phase 0 spike measured a cold capture at ~74 ms and ~5 % of warm captures
///    over one 60 Hz frame, so a synchronous capture here is the blank-first-frame
///    bug, not a theoretical one.
/// 3. **Switch running.** Three snapshot layers under one track transform. Nothing
///    re-rasterises, which is what lets row 54's recoil be a plain scale.
/// 4. **Settle.** The new centre's live view is mounted; row 115 bounds this at
///    100 ms from settle, so a five-press burst cannot leave the centre frozen.
@MainActor
final class CarouselLiveSwapCoordinator {
    private let mount: CarouselPaneMount
    private let cache: CarouselSnapshotCache

    private(set) var isSwitching = false

    init(mount: CarouselPaneMount, cache: CarouselSnapshotCache) {
        self.mount = mount
        self.cache = cache
    }

    /// Row 115's assertion: one live view at rest, zero during a switch.
    var attachedLiveViewCount: Int { mount.attachedLiveViewCount }

    /// Transition 1. Mounts the centre's live surface and paints every flank from
    /// the cache. Safe to call repeatedly; mounting the already-mounted panel is a
    /// no-op.
    func settleAtRest(
        track: CarouselTrackView,
        panelForSession: (CarouselSession) -> TerminalPanel?
    ) {
        isSwitching = false
        for (slot, card) in track.cards {
            guard let session = card.session else { continue }
            if slot == 0 {
                // The live view covers the body, so neither a snapshot nor the
                // placeholder is wanted underneath it.
                card.terminalBody.setSnapshot(nil, backingScale: 1)
                card.terminalBody.setPlaceholder(nil)
                if let panel = panelForSession(session) {
                    mount.mount(panel: panel, in: card.terminalBody)
                }
            } else {
                let image = cache.image(for: session.resourceId)
                card.terminalBody.setSnapshot(
                    image,
                    backingScale: cache.backingScale(for: session.resourceId)
                )
                // Row 10's ruling: a session never centred in this app run has no
                // pixels to capture, so it shows the placeholder rather than a black
                // body. A real capture always wins.
                card.terminalBody.setPlaceholder(image == nil ? session : nil)
            }
        }
    }

    /// Transition 2. Called on the keypress frame, before the track starts moving.
    /// Uses the warm capture only - it never takes one.
    func beginSwitch(track: CarouselTrackView) {
        isSwitching = true
        mount.unmount()
        for card in track.cards.values {
            guard let session = card.session else { continue }
            let image = cache.image(for: session.resourceId)
            card.terminalBody.setSnapshot(
                image,
                backingScale: cache.backingScale(for: session.resourceId)
            )
            card.terminalBody.setPlaceholder(image == nil ? session : nil)
        }
    }

    /// Transition 1's warm-keeping half. Refreshes the centre card's capture at the
    /// cache's own <= 4 Hz rate, and only while at rest: a capture during a switch
    /// would record a moving track.
    func refreshCentreSnapshot(track: CarouselTrackView, window: NSWindow?) {
        guard !isSwitching,
              let window,
              let card = track.centreCard,
              let session = card.session else { return }
        cache.refresh(resourceId: session.resourceId, view: card.terminalBody, in: window) { [weak card] in
            // The centre is live, so it does not paint the capture. Refreshing it is
            // purely so transition 2 has something warm to swap in.
            _ = card
        }
        cache.prune(keeping: Set(track.sessions.map(\.resourceId)))
    }
}
