// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// The four carousel chords, resolved once and passed to the router.
///
/// Injected rather than read from `UserDefaults` inside the router so the
/// routing tests assert routing and nothing else. `live` is the production
/// resolution and goes through `KeyboardShortcutSettings.shortcut(for:)`, which
/// honours a user rebinding in Settings or `~/.config/cmux/cmux.json` — the
/// AGENTS.md shortcut policy.
struct CarouselShortcutBindings: Equatable {
    var navigatePrevious: StoredShortcut
    var navigateNext: StoredShortcut
    var toggleGrid: StoredShortcut
    var toggleCarouselMode: StoredShortcut

    @MainActor
    static var live: CarouselShortcutBindings {
        CarouselShortcutBindings(
            navigatePrevious: KeyboardShortcutSettings.shortcut(for: .carouselNavigatePrevious),
            navigateNext: KeyboardShortcutSettings.shortcut(for: .carouselNavigateNext),
            toggleGrid: KeyboardShortcutSettings.shortcut(for: .carouselToggleGrid),
            toggleCarouselMode: KeyboardShortcutSettings.shortcut(for: .toggleCarouselLayout)
        )
    }

    /// The contract's defaults, independent of any persisted override. Used by
    /// the collision test so a user's local rebinding cannot make it pass.
    static var contractDefaults: CarouselShortcutBindings {
        CarouselShortcutBindings(
            navigatePrevious: KeyboardShortcutSettings.Action.carouselNavigatePrevious.defaultShortcut,
            navigateNext: KeyboardShortcutSettings.Action.carouselNavigateNext.defaultShortcut,
            toggleGrid: KeyboardShortcutSettings.Action.carouselToggleGrid.defaultShortcut,
            toggleCarouselMode: KeyboardShortcutSettings.Action.toggleCarouselLayout.defaultShortcut
        )
    }
}
