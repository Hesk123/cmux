// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

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

    /// Row 114's fallback chord set, for a user whose Ghostty config shadows
    /// the primary grid or mode chord. Navigation keeps its chords (nothing
    /// shadows arrows); grid and mode move to Ctrl+Cmd+Y and Ctrl+Cmd+J, both
    /// confirmed free in the default table and against macOS system bindings
    /// (D-15's spare list). Selected by the user's Settings rebinding, which
    /// the ShortcutAction registration makes visible to the conflict
    /// detector; the coordinator logs whichever set is live at init.
    static var fallback: CarouselShortcutBindings {
        var bindings = CarouselShortcutBindings.contractDefaults
        bindings.toggleGrid = StoredShortcut(key: "y", command: true, shift: false, option: false, control: true)
        bindings.toggleCarouselMode = StoredShortcut(key: "j", command: true, shift: false, option: false, control: true)
        return bindings
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
