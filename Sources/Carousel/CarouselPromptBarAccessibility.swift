// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Accessibility identifiers the H3 XCUITests address the prompt bar by.
///
/// cmux already uses `accessibilityIdentifier` in 41 source files, so element
/// geometry is readable through `XCUIElement.frame` — which is how CONTRACT
/// rows 32-35 are measured without a screenshot.
enum CarouselPromptBarAccessibility {
    static let bar = "carousel.promptBar"
    static let textField = "carousel.promptBar.field"
    static let sessionChip = "carousel.promptBar.sessionChip"
    static let actionButton = "carousel.promptBar.actionButton"
}
