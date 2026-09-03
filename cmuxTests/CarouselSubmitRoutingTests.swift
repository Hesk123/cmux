// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit
import CmuxTerminal
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Records every write, so a test can assert not only that the right surface
/// received a line but that no sibling did.
@MainActor
final class RecordingSubmitSurface: TextBoxSubmitSurfaceControlling {
    let sessionId: String
    private(set) var sentText: [String] = []
    private(set) var sentKeyText: [String] = []
    private(set) var sentNamedKeys: [String] = []

    init(sessionId: String) {
        self.sessionId = sessionId
    }

    var clipboardReadGeneration: Int { 0 }
    var textBoxSubmitObservationWindow: NSWindow? { nil }
    var textBoxSubmitTerminalSurface: TerminalSurface? { nil }

    func visibleText() -> String? { nil }

    @discardableResult
    func sendKeyText(_ text: String) -> Bool {
        sentKeyText.append(text)
        return true
    }

    @discardableResult
    func sendText(_ text: String) -> Bool {
        sentText.append(text)
        return true
    }

    @discardableResult
    func sendNamedKey(_ keyName: String) -> TerminalSurface.NamedKeySendResult {
        sentNamedKeys.append(keyName)
        return .sent
    }

    @discardableResult
    func performBindingAction(_ action: String) -> Bool { true }
}

/// CONTRACT rows 6, 50 (routing half) and 61.
@MainActor
@Suite("Carousel submit routing")
struct CarouselSubmitRoutingTests {
    @Test("Return goes to the centred surface and to no other")
    func sendReachesOnlyTheCentredSurface() {
        let gmail = RecordingSubmitSurface(sessionId: "gmail")
        let slack = RecordingSubmitSurface(sessionId: "slack")
        let stub = CarouselCentreStub(
            sessionId: "gmail",
            displayName: "Gmail",
            surface: gmail
        )
        let controller = CarouselSubmitController(centre: stub)

        #expect(controller.sendText("canary-one"))

        #expect(gmail.sentText == ["canary-one"])
        #expect(slack.sentText.isEmpty, "a sibling session received the line")
    }

    /// The failure this type exists to prevent: a controller that captured its
    /// target at construction keeps writing to the session that was centred
    /// when the prompt bar was built.
    @Test("The target is resolved at send time, not at construction")
    func targetIsResolvedPerSend() {
        let gmail = RecordingSubmitSurface(sessionId: "gmail")
        let slack = RecordingSubmitSurface(sessionId: "slack")
        let stub = CarouselCentreStub(sessionId: "gmail", displayName: "Gmail", surface: gmail)
        let controller = CarouselSubmitController(centre: stub)

        controller.sendText("before-switch")

        stub.centredSessionId = "slack"
        stub.centredSessionDisplayName = "Slack"
        stub.centredSubmitSurface = slack

        controller.sendText("after-switch")

        #expect(gmail.sentText == ["before-switch"])
        #expect(slack.sentText == ["after-switch"])
    }

    @Test("The bound session id follows the centred card through every switch")
    func boundSessionFollowsTheCentre() {
        let stub = CarouselCentreStub(sessionId: "gmail", displayName: "Gmail")
        let controller = CarouselSubmitController(centre: stub)

        #expect(controller.boundSessionId == "gmail")

        for id in ["lovable", "calendar", "notion", "slack", "figma"] {
            stub.centredSessionId = id
            #expect(controller.boundSessionId == id)
        }
    }

    /// Negative control. Without it the suite would pass on a controller that
    /// silently fell back to some other surface when nothing is centred — which
    /// is exactly how a wrong-pty write would look green.
    @Test("With nothing centred the controller refuses rather than falling back")
    func emptyCarouselRefusesToSend() {
        let orphan = RecordingSubmitSurface(sessionId: "orphan")
        let stub = CarouselCentreStub(sessionId: nil, displayName: nil, surface: nil, sessionCount: 0)
        let controller = CarouselSubmitController(centre: stub)

        #expect(controller.sendText("must-not-land") == false)
        #expect(controller.sendKeyText("must-not-land") == false)
        #expect(controller.sendNamedKey("enter") == .surfaceUnavailable)
        #expect(controller.boundSessionId == nil)
        #expect(orphan.sentText.isEmpty)
    }

    @Test("Every write verb forwards to the centred surface")
    func allVerbsForward() {
        let gmail = RecordingSubmitSurface(sessionId: "gmail")
        let stub = CarouselCentreStub(surface: gmail)
        let controller = CarouselSubmitController(centre: stub)

        controller.sendText("text")
        controller.sendKeyText("keys")
        #expect(controller.sendNamedKey("enter") == .sent)

        #expect(gmail.sentText == ["text"])
        #expect(gmail.sentKeyText == ["keys"])
        #expect(gmail.sentNamedKeys == ["enter"])
    }
}
