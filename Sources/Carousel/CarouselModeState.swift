// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import Foundation

/// The carousel mode toggle, scoped to a **window** rather than to a workspace.
///
/// `WorkspaceLayoutMode` was the obvious home and is the wrong one:
/// `Sources/Workspace.swift:2666` publishes it per workspace and the canvas is
/// scoped to one workspace's panels, whereas the carousel's cards come from agent
/// surfaces across every mounted workspace in the window (row 105, D-9). A
/// workspace-scoped flag would have made row 105 unsatisfiable by construction.
///
/// The toggle travels as a notification carrying the window, so
/// `AppDelegate+CarouselShortcutRouting` can route the chord without holding a
/// reference into the SwiftUI tree, and `ContentView` observes it with one modifier.
/// `Sources/AppDelegate.swift` is 19,942 lines and is not edited for this.
@MainActor
enum CarouselModeState {
    /// Posted with the target `NSWindow` as the notification object. A nil object
    /// means "the key window", which is what a menu item sends.
    static let toggleNotification = Notification.Name("com.cmux.carousel.toggleMode")

    static func postToggle(window: NSWindow?) {
        NotificationCenter.default.post(name: toggleNotification, object: window)
    }
    static var fullscreenToggle: (NSWindow) -> Void = { win in win.toggleFullScreen(nil) }


    /// Row 28. The card is an `NSVisualEffectView` with `.behindWindow` blending,
    /// which is the only material that samples the **desktop** rather than the app's
    /// own backdrop - and that is exactly the difference row 28's two-wallpaper test
    /// discriminates. `.behindWindow` only reaches the desktop through a window that
    /// is not opaque, and cmux's is, so the mode toggle flips it.
    ///
    /// The change is scoped to carousel mode and reversed on exit, so cmux's normal
    /// chrome keeps its opaque window and its own `WindowBackdropLayer` untouched.
    /// The previous values are captured rather than assumed, because a window that
    /// entered carousel mode already non-opaque must not be "restored" to opaque.
    static func applyTranslucency(_ active: Bool, to window: NSWindow?) {
        guard let window else { return }
        if active {
            let firstEntry = restoreStateByWindow[ObjectIdentifier(window)] == nil
            if firstEntry {
                restoreStateByWindow[ObjectIdentifier(window)] = RestoreState(
                    isOpaque: window.isOpaque,
                    backgroundColor: window.backgroundColor,
                    titleVisibility: window.titleVisibility,
                    closeHidden: window.standardWindowButton(.closeButton)?.isHidden ?? false,
                    miniaturizeHidden: window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false,
                    zoomHidden: window.standardWindowButton(.zoomButton)?.isHidden ?? false,
                    wasFullScreen: window.styleMask.contains(.fullScreen),
                    enteredFullscreen: false
                )
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titleVisibility = .hidden
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if firstEntry, let was = restoreStateByWindow[ObjectIdentifier(window)]?.wasFullScreen, !was {
                if var state = restoreStateByWindow[ObjectIdentifier(window)] {
                    state.enteredFullscreen = true
                    restoreStateByWindow[ObjectIdentifier(window)] = state
                }
                fullscreenToggle(window)
            }
            return
        }
        guard let restore = restoreStateByWindow.removeValue(forKey: ObjectIdentifier(window)) else {
            return
        }
        window.isOpaque = restore.isOpaque
        window.backgroundColor = restore.backgroundColor
        window.titleVisibility = restore.titleVisibility
        window.standardWindowButton(.closeButton)?.isHidden = restore.closeHidden
        window.standardWindowButton(.miniaturizeButton)?.isHidden = restore.miniaturizeHidden
        window.standardWindowButton(.zoomButton)?.isHidden = restore.zoomHidden
        if restore.enteredFullscreen {
            fullscreenToggle(window)
        }
    }

    private struct RestoreState {
        let isOpaque: Bool
        let backgroundColor: NSColor?
        let titleVisibility: NSWindow.TitleVisibility
        let closeHidden: Bool
        let miniaturizeHidden: Bool
        let zoomHidden: Bool
        let wasFullScreen: Bool
        var enteredFullscreen: Bool
    }

    private static var restoreStateByWindow: [ObjectIdentifier: RestoreState] = [:]

    /// Whether a toggle notification is addressed to `window`.
    static func toggleApplies(_ notification: Notification, to window: NSWindow?) -> Bool {
        guard let window else { return false }
        guard let target = notification.object as? NSWindow else {
            return window.isKeyWindow
        }
        return target === window
    }
}
