// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit
import CmuxTerminal

/// Routes everything the prompt bar submits to the **currently centred** card's
/// pty — CONTRACT rows 6, 50 (routing half) and 61.
///
/// The whole point of this type is that it resolves the target on every call
/// instead of holding one. A controller that captured a surface at construction
/// would keep writing to whichever session happened to be centred when the
/// prompt bar was built, which is precisely the failure row 6 tests for by
/// asserting the string appears in the receiving session's transcript **and in
/// no sibling's**.
///
/// When nothing is centred the controller refuses. It never falls back to
/// "some" surface: a fallback would make row 6 pass while writing to the wrong
/// pty, and the empty carousel is a real state (row 116, N = 0).
@MainActor
final class CarouselSubmitController: TextBoxSubmitSurfaceControlling {
    private weak var centre: CarouselCentreProviding?

    init(centre: CarouselCentreProviding) {
        self.centre = centre
    }

    /// The centred card's live surface, re-resolved on every access.
    private var target: TextBoxSubmitSurfaceControlling? {
        centre?.centredSubmitSurface
    }

    /// The session the prompt bar is bound to right now. Row 6 asserts this
    /// equals the centred card's id after every switch.
    var boundSessionId: String? {
        centre?.centredSessionId
    }

    var clipboardReadGeneration: Int {
        target?.clipboardReadGeneration ?? 0
    }

    var textBoxSubmitObservationWindow: NSWindow? {
        target?.textBoxSubmitObservationWindow
    }

    var textBoxSubmitTerminalSurface: TerminalSurface? {
        target?.textBoxSubmitTerminalSurface
    }

    func visibleText() -> String? {
        target?.visibleText()
    }

    @discardableResult
    func sendKeyText(_ text: String) -> Bool {
        target?.sendKeyText(text) ?? false
    }

    @discardableResult
    func sendText(_ text: String) -> Bool {
        target?.sendText(text) ?? false
    }

    @discardableResult
    func sendNamedKey(_ keyName: String) -> TerminalSurface.NamedKeySendResult {
        target?.sendNamedKey(keyName) ?? .surfaceUnavailable
    }

    @discardableResult
    func performBindingAction(_ action: String) -> Bool {
        target?.performBindingAction(action) ?? false
    }

    @discardableResult
    func performExplicitInputBindingAction(_ action: String) -> Bool {
        target?.performExplicitInputBindingAction(action) ?? false
    }
}
