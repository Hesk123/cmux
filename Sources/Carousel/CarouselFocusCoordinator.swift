// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit
import Observation

/// Owns the carousel's focus state and applies every key event's routing
/// decision — CONTRACT rows 5, 61 and 114, under ruling D-1.
///
/// The five transitions row 114 drives are the five mutating entry points here:
/// `enterCarouselMode`, `focusCentredTerminal`, `handleKeyEvent` for Esc,
/// `handleKeyEvent` for a navigation chord, and `handleKeyEvent` for ordinary
/// text. Row 61's assertion — the prompt bar keeps focus through a switch — is
/// structural: `.navigateCarousel` does not touch `focusOwner`.
@Observable
@MainActor
final class CarouselFocusCoordinator {
    /// Ruling D-1: the prompt bar owns focus on entering carousel mode.
    private(set) var focusOwner: CarouselFocusOwner = .promptBar

    /// Which fallback chord set is live. Logged so the row-114 clause about a
    /// user's Ghostty config shadowing ⌃⌘M or ⌃⌘K is observable rather than
    /// silent.
    private(set) var activeBindings: CarouselShortcutBindings

    private weak var centre: CarouselCentreProviding?

    init(centre: CarouselCentreProviding, bindings: CarouselShortcutBindings) {
        self.centre = centre
        self.activeBindings = bindings
    }

    // MARK: - Transitions

    /// Entering carousel mode hands focus to the prompt bar (D-1).
    func enterCarouselMode() {
        focusOwner = .promptBar
    }

    /// Clicking a card hands first responder to that card's terminal, where
    /// every key including the arrows goes to the pty (D-1, row 50).
    func focusCentredTerminal() {
        focusOwner = .centredTerminal
    }

    /// Esc from a focused terminal returns focus to the prompt bar (D-1).
    func returnFocusToPromptBar() {
        focusOwner = .promptBar
    }

    // MARK: - Key handling

    /// Applies one key event. Returns the routing taken so a caller can decide
    /// whether to consume the event, and so tests read the decision rather than
    /// inferring it from side effects.
    @discardableResult
    func handleKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        eventCharacter: String?
    ) -> CarouselKeyRouting {
        let routing = CarouselKeyRouter.route(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            eventCharacter: eventCharacter,
            focusOwner: focusOwner,
            bindings: activeBindings
        )

        switch routing {
        case .navigateCarousel(let direction):
            // Row 61: navigation never steals focus. `focusOwner` is untouched
            // on purpose — the composed line and the caret both survive.
            navigate(direction)
        case .restoreFocusToPromptBar:
            returnFocusToPromptBar()
        case .toggleGrid, .toggleCarouselMode, .promptBarField, .centredPty:
            break
        }

        return routing
    }

    /// Row 116: navigation is a no-op below two cards and must not animate.
    func navigate(_ direction: CarouselNavigationDirection) {
        guard let centre, centre.carouselSessionCount >= 2 else { return }
        centre.navigateCarousel(direction)
    }

    /// True when the event should be swallowed rather than passed on to the
    /// text field or the pty.
    static func consumesEvent(_ routing: CarouselKeyRouting) -> Bool {
        switch routing {
        case .navigateCarousel, .toggleGrid, .toggleCarouselMode, .restoreFocusToPromptBar:
            true
        case .promptBarField, .centredPty:
            false
        }
    }
}
