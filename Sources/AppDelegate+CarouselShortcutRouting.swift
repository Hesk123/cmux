// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit

/// Routing for the carousel's chords, in its own file.
///
/// `Sources/AppDelegate.swift` is 19,942 lines and nobody edits it; the canvas puts
/// its shortcut routing in `Sources/AppDelegate+CanvasShortcutRouting.swift` for the
/// same reason, and this mirrors that file.
///
/// The chords themselves (⌃⌘K toggle, ⌃⌘←/→ navigate, ⌃⌘M grid) are declared in
/// `KeyboardShortcutSettings` per AGENTS.md's shortcut policy - every cmux-owned
/// shortcut is settable in Settings and in `~/.config/cmux/cmux.json`. D-15 checked
/// them against the whole default table and against macOS system bindings: ⌃⌘G is
/// taken at `KeyboardShortcutSettings.swift` by `.newWorkspaceGroup`, which is why
/// grid is ⌃⌘M and not the reference video's ⌘G, and the ⌥⌘ arrow bindings (`.focusLeft/Right/Up/Down`) do not collide
/// with ⌃⌘←/→, which is what keeps those chords free. ⌘⇧←/→ were rejected: AppKit
/// binds them to select-to-beginning/end-of-line in a text field, and D-1 puts focus
/// in exactly that field by default.
@MainActor
extension AppDelegate {
    /// ⌃⌘K. Swaps the window's content region between cmux's normal workspace
    /// chrome and the carousel, which is Dawid's answer to Q3: a toggled mode
    /// *beside* the existing sidebar and tab chrome, not a replacement for it.
    @discardableResult
    func performCarouselModeToggleShortcut() -> Bool {
        let window = shortcutRoutingActiveWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let window else { return false }
        CarouselModeState.postToggle(window: window)
        return true
    }

    /// ⌃⌘← / ⌃⌘→. Row 5. Bare arrows never reach here: D-15a dropped bare-arrow
    /// navigation outright, because emptiness is an invisible mode that flips on
    /// every keystroke - type one character and ← moves a cursor, delete it and ←
    /// slides the carousel.
    @discardableResult
    func performCarouselNavigateShortcut(_ direction: CarouselNavigationDirection) -> Bool {
        let window = shortcutRoutingActiveWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let window else { return false }
        CarouselNavigationRouter.post(direction: direction, window: window)
        return true
    }
}

/// Carries a navigation chord from the app-level shortcut dispatcher to whichever
/// window's carousel is mounted, without either side holding a reference to the
/// other. Same shape as ``CarouselModeState``, and for the same reason.
@MainActor
enum CarouselNavigationRouter {
    static let notification = Notification.Name("com.cmux.carousel.navigate")
    static let directionKey = "direction"

    static func post(direction: CarouselNavigationDirection, window: NSWindow?) {
        NotificationCenter.default.post(
            name: notification,
            object: window,
            userInfo: [directionKey: direction == .next]
        )
    }

    /// Decodes a posted notification, returning nil when it is addressed elsewhere.
    static func direction(from notification: Notification, for window: NSWindow?) -> CarouselNavigationDirection? {
        guard CarouselModeState.toggleApplies(notification, to: window) else { return nil }
        guard let isNext = notification.userInfo?[directionKey] as? Bool else { return nil }
        return isNext ? .next : .previous
    }
}
