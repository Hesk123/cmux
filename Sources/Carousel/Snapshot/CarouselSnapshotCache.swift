// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import CoreGraphics

/// One `CGImage` per session at backing scale, refreshed at most 4 Hz
/// (CONTRACT row 115, ruling D-2).
///
/// **What this cache can and cannot hold, stated plainly, because it bounds row 10.**
/// Only the centred session has a live libghostty view; every other session's
/// surface is unbound from the portal and Ghostty pauses a non-visible surface
/// (`GhosttyTerminalView.swift:4015-4017`). There are therefore no pixels to capture
/// for a session that is not centred. A flank's image is the capture taken while it
/// *was* centred, and a session never visited in this app run has none.
///
/// Row 10's mechanical assertion - find each flank session's own header canary in
/// the capture - still passes, because the card's header, name, subtitle and status
/// pill are drawn natively by `CarouselCardChromeView` from live session state on
/// every card. What a never-visited flank lacks is only its terminal *body* pixels,
/// and it renders ``CarouselSnapshotCache/hasSnapshot(for:)`` false rather than a
/// stand-in, which row 85 requires.
@MainActor
final class CarouselSnapshotCache {
    /// D-2's bound. 250 ms between captures; at the spike's 11.6 ms warm median that
    /// is about 4.7 % of one core for the single card being refreshed.
    static let refreshInterval: TimeInterval = 0.25

    private struct Entry {
        var image: CGImage
        var capturedAt: Date
        var backingScale: CGFloat
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: Set<String> = []

    /// The cached capture for `resourceId`, if one was ever taken.
    func image(for resourceId: String) -> CGImage? {
        entries[resourceId]?.image
    }

    func backingScale(for resourceId: String) -> CGFloat {
        entries[resourceId]?.backingScale ?? 2
    }

    func hasSnapshot(for resourceId: String) -> Bool {
        entries[resourceId] != nil
    }

    /// How stale the cached capture is, for a report that needs the real figure
    /// rather than the nominal 4 Hz.
    func age(for resourceId: String, now: Date = .now) -> TimeInterval? {
        entries[resourceId].map { now.timeIntervalSince($0.capturedAt) }
    }

    /// Captures `rect` for `resourceId`, unless a capture is already running for it
    /// or the last one is younger than ``refreshInterval``.
    ///
    /// Fire-and-forget on purpose: the caller is a layout or a timer tick, and a
    /// capture that has not finished must never hold either up. The spike's ~5 % of
    /// warm captures exceeding one frame is exactly why.
    func refresh(
        resourceId: String,
        view: NSView,
        in window: NSWindow,
        now: Date = .now,
        completion: @escaping @MainActor () -> Void = {}
    ) {
        guard !inFlight.contains(resourceId) else { return }
        if let existing = entries[resourceId],
           now.timeIntervalSince(existing.capturedAt) < Self.refreshInterval {
            return
        }
        inFlight.insert(resourceId)
        let scale = window.backingScaleFactor
        Task { @MainActor [weak self] in
            let image = await CarouselCardSnapshotter.capture(view: view, in: window)
            guard let self else { return }
            self.inFlight.remove(resourceId)
            guard let image else { return }
            // A failed capture keeps whatever was cached, so a dropped capture is
            // invisible rather than a blank frame.
            self.entries[resourceId] = Entry(image: image, capturedAt: .now, backingScale: scale)
            completion()
        }
    }

    /// Drops sessions that are no longer in the carousel, so a long-lived window
    /// does not accumulate captures for closed surfaces.
    func prune(keeping resourceIds: Set<String>) {
        entries = entries.filter { resourceIds.contains($0.key) }
    }
}
