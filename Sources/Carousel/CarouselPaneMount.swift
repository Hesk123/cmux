// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit

/// Mounts the live libghostty surface into the centre card's body, and hands it back
/// on unmount. CONTRACT rows 50 and 115.
///
/// **One terminal, in one place.** `TerminalPanel.hostedView` is a single
/// `GhosttySurfaceScrollView` and an `NSView` has one superview, so the carousel can
/// only ever own one at a time. Under D-2 that is exactly what it wants: the centre
/// card hosts the live view and every flank is a snapshot layer, so at any instant
/// the app has one terminal in an unusual place instead of three, and the blast
/// radius on the portal, on focus and on agent hibernation shrinks by two thirds.
///
/// The mechanism is the canvas's, not a new one. `Sources/Canvas/CanvasPaneContent.swift`
/// hit the same wall - the window portal resizes a hosted terminal to its *visible
/// intersection*, which on a clipping container reflows the grid at the edge - and
/// resolved it by detaching from the portal and parenting the view directly so the
/// container crops instead. Plan section 2.4 names that path for this build too.
///
/// The centre card is never clipped and never transformed while a view is mounted
/// (all three cards are snapshots during a switch), so the clamp and the reflow the
/// canvas had to design around cannot fire here at all.
@MainActor
final class CarouselPaneMount {
    private(set) var mountedPanelId: UUID?
    private weak var mountedPanel: TerminalPanel?
    private weak var mountedContainer: NSView?

    /// Row 115's assertion reads this: exactly one at rest, zero during a switch.
    var attachedLiveViewCount: Int { mountedPanel == nil ? 0 : 1 }

    /// Called when the mounted terminal takes keyboard focus, so U3's focus
    /// coordinator can move first responder off the prompt bar (row 114).
    var onTerminalFocus: ((UUID) -> Void)?

    /// Mounts `panel`'s live surface into `container`, unmounting whatever was there.
    func mount(panel: TerminalPanel, in container: NSView) {
        if mountedPanelId == panel.id, mountedContainer === container { return }
        unmount()

        let hostedView = panel.hostedView
        // Detach from the window portal before parenting, exactly as the canvas
        // does. Without this the portal keeps writing a frame derived from an anchor
        // that no longer exists in the layout.
        TerminalWindowPortalRegistry.detach(hostedView: hostedView)
        hostedView.setFocusHandler { [weak self] in
            self?.onTerminalFocus?(panel.id)
        }
        CanvasPaneContentMount.attachTerminalView(hostedView, to: container) { view in
            view.setVisibleInUI(true)
        }
        hostedView.setActive(true)
        panel.surface.applyVisibilityOcclusion(true)

        mountedPanel = panel
        mountedPanelId = panel.id
        mountedContainer = container
    }

    /// Unmounts the live view. Mirrors `CanvasPaneContentMount.unmount()` so the
    /// surface is handed back in the same state the split layout expects to find it.
    func unmount() {
        guard let panel = mountedPanel else { return }
        let hostedView = panel.hostedView
        hostedView.setActive(false)
        hostedView.setFocusHandler(nil)
        hostedView.setInactiveOverlay(color: .clear, opacity: 0, visible: false)
        // Leave the surface rendering rather than occluded: an occluded surface
        // stops drawing, and the next capture of it would be of a paused terminal.
        panel.surface.applyVisibilityOcclusion(true)
        hostedView.removeFromSuperview()

        mountedPanel = nil
        mountedPanelId = nil
        mountedContainer = nil
    }
}
