// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Stub track. U1 is not built yet, so this stands in for it and implements the
/// frozen `CarouselCentreProviding` interface exactly as U1 must.
@MainActor
final class CarouselCentreStub: CarouselCentreProviding {
    var centredSessionId: String?
    var centredSessionDisplayName: String?
    var centredSubmitSurface: TextBoxSubmitSurfaceControlling?
    var carouselSessionCount: Int
    private(set) var navigations: [CarouselNavigationDirection] = []

    init(
        sessionId: String? = "session-a",
        displayName: String? = "Gmail",
        surface: TextBoxSubmitSurfaceControlling? = nil,
        sessionCount: Int = 6
    ) {
        self.centredSessionId = sessionId
        self.centredSessionDisplayName = displayName
        self.centredSubmitSurface = surface
        self.carouselSessionCount = sessionCount
    }

    func navigateCarousel(_ direction: CarouselNavigationDirection) {
        navigations.append(direction)
    }
}

/// CONTRACT rows 5, 61 and 114, under rulings D-1 and D-15a.
@MainActor
@Suite("Carousel focus and key routing")
struct CarouselFocusRoutingTests {
    private static let bindings = CarouselShortcutBindings.contractDefaults

    private static let controlCommand: NSEvent.ModifierFlags = [.control, .command]

    private func makeCoordinator(
        sessionCount: Int = 6
    ) -> (CarouselFocusCoordinator, CarouselCentreStub) {
        let stub = CarouselCentreStub(sessionCount: sessionCount)
        let coordinator = CarouselFocusCoordinator(centre: stub, bindings: Self.bindings)
        return (coordinator, stub)
    }

    // MARK: - C1: registered-action dispatch

    @Test("Registered navigation actions reach the track")
    func registeredNavigationActionsDispatch() {
        let (coordinator, stub) = makeCoordinator()
        #expect(coordinator.performRegisteredAction(.carouselNavigateNext) == true)
        #expect(coordinator.performRegisteredAction(.carouselNavigatePrevious) == true)
        #expect(stub.navigations == [.next, .previous])
    }

    @Test("Grid and mode toggles are reported, not absorbed")
    func registeredTogglesAreNotAbsorbed() {
        // Owned by U6 (grid presenter) and U1 (mode toggle). The coordinator
        // returns false so the mode-lifecycle call site routes them onward.
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.performRegisteredAction(.carouselToggleGrid) == false)
        #expect(coordinator.performRegisteredAction(.toggleCarouselLayout) == false)
    }

    @Test("Unrelated actions are refused")
    func unrelatedActionsAreRefused() {
        let (coordinator, stub) = makeCoordinator()
        #expect(coordinator.performRegisteredAction(.toggleCanvasLayout) == false)
        #expect(stub.navigations.isEmpty)
    }

    // MARK: - Row 114: the five transitions

    @Test("Entering carousel mode gives the prompt bar focus")
    func promptBarOwnsFocusByDefault() {
        let (coordinator, _) = makeCoordinator()
        coordinator.enterCarouselMode()
        #expect(coordinator.focusOwner == .promptBar)
    }

    @Test("Clicking a card focuses that terminal; Esc returns focus to the bar")
    func clickThenEscapeRoundTrip() {
        let (coordinator, _) = makeCoordinator()
        coordinator.enterCarouselMode()

        coordinator.focusCentredTerminal()
        #expect(coordinator.focusOwner == .centredTerminal)

        let routing = coordinator.handleKeyEvent(
            keyCode: CarouselKeyRouter.KeyCode.escape,
            modifierFlags: [],
            eventCharacter: nil
        )
        #expect(routing == .restoreFocusToPromptBar)
        #expect(coordinator.focusOwner == .promptBar)
    }

    @Test("A modified Esc stays terminal input rather than stealing focus")
    func modifiedEscapeReachesThePty() {
        let (coordinator, _) = makeCoordinator()
        coordinator.focusCentredTerminal()

        let routing = coordinator.handleKeyEvent(
            keyCode: CarouselKeyRouter.KeyCode.escape,
            modifierFlags: [.option],
            eventCharacter: nil
        )
        #expect(routing == .centredPty)
        #expect(coordinator.focusOwner == .centredTerminal)
    }

    // MARK: - Row 61 + row 114: the chord never reaches the text field

    @Test("Ctrl+Cmd arrows navigate even while the prompt bar holds focus")
    func navigationChordBeatsTheTextField() {
        let (coordinator, stub) = makeCoordinator()
        coordinator.enterCarouselMode()

        let previous = coordinator.handleKeyEvent(
            keyCode: CarouselKeyRouter.KeyCode.leftArrow,
            modifierFlags: Self.controlCommand,
            eventCharacter: nil
        )
        let next = coordinator.handleKeyEvent(
            keyCode: CarouselKeyRouter.KeyCode.rightArrow,
            modifierFlags: Self.controlCommand,
            eventCharacter: nil
        )

        #expect(previous == .navigateCarousel(.previous))
        #expect(next == .navigateCarousel(.next))
        #expect(stub.navigations == [.previous, .next])
        // Row 61: navigation never steals focus.
        #expect(coordinator.focusOwner == .promptBar)
    }

    @Test("Five navigation presses each move the track once")
    func fivePressBurstMovesFiveTimes() {
        let (coordinator, stub) = makeCoordinator()
        coordinator.enterCarouselMode()

        for _ in 0..<5 {
            coordinator.handleKeyEvent(
                keyCode: CarouselKeyRouter.KeyCode.rightArrow,
                modifierFlags: Self.controlCommand,
                eventCharacter: nil
            )
        }
        #expect(stub.navigations == Array(repeating: .next, count: 5))
    }

    // MARK: - Row 114 / ruling D-15a: bare arrows, two states

    @Test("Prompt bar focused: bare arrows edit text and never navigate")
    func bareArrowsEditTheFieldWhenTheBarHasFocus() {
        let (coordinator, stub) = makeCoordinator()
        coordinator.enterCarouselMode()

        for keyCode in [
            CarouselKeyRouter.KeyCode.leftArrow,
            CarouselKeyRouter.KeyCode.rightArrow,
        ] {
            let routing = coordinator.handleKeyEvent(
                keyCode: keyCode,
                modifierFlags: [],
                eventCharacter: nil
            )
            #expect(routing == .promptBarField)
        }
        #expect(stub.navigations.isEmpty, "bare arrows must never move the carousel")
    }

    @Test("Terminal focused: bare arrows reach that pty")
    func bareArrowsReachThePtyWhenTheTerminalHasFocus() {
        let (coordinator, stub) = makeCoordinator()
        coordinator.focusCentredTerminal()

        for keyCode in CarouselKeyRouter.KeyCode.arrows {
            let routing = coordinator.handleKeyEvent(
                keyCode: keyCode,
                modifierFlags: [],
                eventCharacter: nil
            )
            #expect(routing == .centredPty)
        }
        #expect(stub.navigations.isEmpty)
    }

    /// Row 114's third assertion, and the one ruling D-15a exists for.
    @Test("Bare arrows never move the carousel in any focus state")
    func bareArrowsNeverNavigateInEitherState() {
        for owner in [CarouselFocusOwner.promptBar, .centredTerminal] {
            for keyCode in CarouselKeyRouter.KeyCode.arrows {
                let routing = CarouselKeyRouter.route(
                    keyCode: keyCode,
                    modifierFlags: [],
                    eventCharacter: nil,
                    focusOwner: owner,
                    bindings: Self.bindings
                )
                switch routing {
                case .navigateCarousel:
                    Issue.record("bare arrow navigated with focus on \(owner)")
                default:
                    break
                }
            }
        }
    }

    /// Emptiness is never a mode: the router takes no text, so there is no
    /// input to vary and `bareArrowsNeverNavigateInEitherState` above is the
    /// assertion that bites. (A previous revision called the router twice with
    /// identical arguments under a "simulated typing" comment; identical inputs
    /// cannot produce different outputs, so it proved nothing and was deleted.)

    // MARK: - Mode chords

    @Test("Ctrl+Cmd+M toggles the grid and Ctrl+Cmd+K toggles carousel mode")
    func modeChordsRoute() {
        let (coordinator, _) = makeCoordinator()
        coordinator.enterCarouselMode()

        #expect(
            coordinator.handleKeyEvent(
                keyCode: 46, modifierFlags: Self.controlCommand, eventCharacter: "m"
            ) == .toggleGrid
        )
        #expect(
            coordinator.handleKeyEvent(
                keyCode: 40, modifierFlags: Self.controlCommand, eventCharacter: "k"
            ) == .toggleCarouselMode
        )
    }

    // MARK: - Row 116

    @Test("Navigation is a no-op below two sessions")
    func navigationNoOpsWithFewerThanTwoCards() {
        for count in [0, 1] {
            let (coordinator, stub) = makeCoordinator(sessionCount: count)
            coordinator.handleKeyEvent(
                keyCode: CarouselKeyRouter.KeyCode.rightArrow,
                modifierFlags: Self.controlCommand,
                eventCharacter: nil
            )
            #expect(stub.navigations.isEmpty, "navigated with \(count) cards")
        }

        let (coordinator, stub) = makeCoordinator(sessionCount: 2)
        coordinator.handleKeyEvent(
            keyCode: CarouselKeyRouter.KeyCode.rightArrow,
            modifierFlags: Self.controlCommand,
            eventCharacter: nil
        )
        #expect(stub.navigations == [.next], "two cards must still navigate")
    }

    @Test("Only chords and Esc are consumed; text and pty keys pass through")
    func consumptionMatchesRouting() {
        #expect(CarouselFocusCoordinator.consumesEvent(.navigateCarousel(.next)))
        #expect(CarouselFocusCoordinator.consumesEvent(.toggleGrid))
        #expect(CarouselFocusCoordinator.consumesEvent(.toggleCarouselMode))
        #expect(CarouselFocusCoordinator.consumesEvent(.restoreFocusToPromptBar))
        #expect(!CarouselFocusCoordinator.consumesEvent(.promptBarField))
        #expect(!CarouselFocusCoordinator.consumesEvent(.centredPty))
    }
}
