// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit

/// The one place carousel-mode key destination is decided (CONTRACT row 114).
///
/// Two properties this type holds by construction rather than by test:
///
/// 1. **Emptiness is never a mode (ruling D-15a).** `route` takes no text and no
///    emptiness flag, so it is not expressible for a bare arrow to navigate when
///    the field happens to be empty. The reversed D-15 clause cannot come back
///    by accident; it would need a new parameter.
/// 2. **A navigation chord never reaches the focused text field (row 114).**
///    Chords are matched *before* the focus-owner fallthrough, so `⌃⌘←` returns
///    `.navigateCarousel` even while the prompt bar holds focus. This is the
///    defect that disqualified `⌘⇧←/→`, which AppKit binds to
///    select-to-beginning/end-of-line in exactly that field.
enum CarouselKeyRouter {
    /// AppKit virtual key codes. Physical, so they are keyboard-layout
    /// independent — the same property `StoredShortcut` relies on for arrows
    /// (`usesPhysicalKeyCodeMatching`, KeyboardShortcutSettings.swift:2000).
    enum KeyCode {
        static let escape: UInt16 = 53
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let downArrow: UInt16 = 125
        static let upArrow: UInt16 = 126

        static let arrows: Set<UInt16> = [leftArrow, rightArrow, downArrow, upArrow]
    }

    static func route(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventCharacter: String?,
        focusOwner: CarouselFocusOwner,
        bindings: CarouselShortcutBindings
    ) -> CarouselKeyRouting {
        func matches(_ shortcut: StoredShortcut) -> Bool {
            shortcut.matches(
                keyCode: keyCode,
                modifierFlags: modifierFlags,
                eventCharacter: eventCharacter
            )
        }

        // Chords win over both focus states. See property 2 above.
        if matches(bindings.navigatePrevious) { return .navigateCarousel(.previous) }
        if matches(bindings.navigateNext) { return .navigateCarousel(.next) }
        if matches(bindings.toggleGrid) { return .toggleGrid }
        if matches(bindings.toggleCarouselMode) { return .toggleCarouselMode }

        switch focusOwner {
        case .promptBar:
            // Every remaining key edits the line, arrows included, whatever the
            // field contains. Ruling D-15a.
            return .promptBarField
        case .centredTerminal:
            if keyCode == KeyCode.escape,
               CarouselKeyRouter.isUnmodified(modifierFlags) {
                return .restoreFocusToPromptBar
            }
            return .centredPty
        }
    }

    /// Esc only returns focus when pressed bare. A modified Esc is terminal
    /// input (⌥Esc and ⌃Esc both mean something to a shell), so swallowing it
    /// would silently break the pty this mode exists to drive.
    private static func isUnmodified(_ flags: NSEvent.ModifierFlags) -> Bool {
        ShortcutStroke.normalizedModifierFlags(from: flags).isEmpty
    }
}
