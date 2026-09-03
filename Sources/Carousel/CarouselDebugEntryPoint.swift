// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-03 for the cmux carousel UI (unit U1: debug entry point for the
// carousel mode toggle, pending U3's KeyboardShortcutSettings registration).

import AppKit

/// A debug-only way into carousel mode, until U3's ⌃⌘K registration merges.
///
/// The real chord is `KeyboardShortcutSettings.Action.toggleCarouselLayout`, which
/// lives on `carousel/u3` — AGENTS.md's shortcut policy requires every cmux-owned
/// shortcut to be registered there, settable in Settings and in
/// `~/.config/cmux/cmux.json`, and U3 owns that file. Declaring a second copy on
/// this branch would be a guaranteed merge conflict for no behaviour.
///
/// Without something, though, carousel mode cannot be entered on this branch at all,
/// which makes every row that needs a running carousel unverifiable. So this
/// installs a **local** event monitor for the same chord, and only when
/// `CMUX_CAROUSEL_DEBUG_TOGGLE` is set. Local rather than global, so it never sees a
/// key press aimed at another app; opt-in, so a normal run behaves exactly as if
/// this file did not exist. It is deleted when U3's registration lands.
@MainActor
enum CarouselDebugEntryPoint {
    static let environmentKey = "CMUX_CAROUSEL_DEBUG_TOGGLE"

    private static var monitor: Any?

    /// True when the debug toggle is armed for this process.
    static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[environmentKey] == "1"
    }

    /// True when the app should launch straight into carousel mode, with no
    /// keystroke. Same flag as `isEnabled`: the toggle already means "carousel
    /// is enterable on this build for debug/test", and the UI tests need the
    /// mode active before they can assert on carousel chrome. A normal launch
    /// never sets the flag, so default behaviour is untouched.
    static func shouldAutoEnterCarousel(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        isEnabled(environment: environment)
    }

    /// Idempotent: installing twice leaves one monitor, so a repeated `task` on a
    /// re-created view cannot stack handlers and toggle the mode twice per press.
    static func installIfEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard isEnabled(environment: environment), monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard matchesToggleChord(event) else { return event }
            CarouselModeState.postToggle(window: event.window ?? NSApp.keyWindow)
            return nil
        }
    }

    static func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// ⌃⌘K, matching D-15's chord exactly. Checked against the four modifiers that
    /// matter rather than equality on the whole mask, so caps lock or a numeric-pad
    /// flag does not silently stop it matching.
    static func matchesToggleChord(_ event: NSEvent) -> Bool {
        matchesToggleChord(
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            modifiers: event.modifierFlags
        )
    }

    static func matchesToggleChord(
        charactersIgnoringModifiers: String?,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard charactersIgnoringModifiers?.lowercased() == "k" else { return false }
        return modifiers.contains(.control)
            && modifiers.contains(.command)
            && !modifiers.contains(.option)
            && !modifiers.contains(.shift)
    }
}
