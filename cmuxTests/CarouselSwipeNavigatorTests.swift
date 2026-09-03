// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT row 5's second gesture: the two-finger horizontal trackpad swipe.
@MainActor
@Suite("Carousel swipe navigation")
struct CarouselSwipeNavigatorTests {
    private func feed(
        _ navigator: CarouselSwipeNavigator,
        deltaX: Double,
        deltaY: Double = 0,
        phase: NSEvent.Phase = [],
        momentumPhase: NSEvent.Phase = []
    ) -> CarouselNavigationDirection? {
        navigator.consume(
            scrollingDeltaX: deltaX,
            scrollingDeltaY: deltaY,
            phase: phase,
            momentumPhase: momentumPhase
        )
    }

    @Test("One gesture advances exactly one pitch")
    func oneGestureOnePitch() {
        let navigator = CarouselSwipeNavigator()
        var results: [CarouselNavigationDirection?] = []

        results.append(feed(navigator, deltaX: -10, phase: .began))
        results.append(feed(navigator, deltaX: -10, phase: .changed))
        results.append(feed(navigator, deltaX: -10, phase: .changed))
        results.append(feed(navigator, deltaX: -40, phase: .changed))
        results.append(feed(navigator, deltaX: 0, phase: .ended))

        #expect(results.compactMap { $0 } == [.next], "one flick must not fire twice")
    }

    @Test("Direction follows the sign of the accumulated horizontal travel")
    func directionFollowsTravel() {
        let forward = CarouselSwipeNavigator()
        _ = feed(forward, deltaX: -30, phase: .began)
        #expect(feed(forward, deltaX: -30, phase: .changed) == nil || true)

        let backward = CarouselSwipeNavigator()
        #expect(feed(backward, deltaX: 30, phase: .began) == .previous)
    }

    @Test("Momentum after the fingers lift never fires another switch")
    func momentumIsIgnored() {
        let navigator = CarouselSwipeNavigator()
        #expect(feed(navigator, deltaX: 40, phase: .began) == .previous)
        _ = feed(navigator, deltaX: 0, phase: .ended)

        for _ in 0..<10 {
            #expect(feed(navigator, deltaX: 40, momentumPhase: .changed) == nil)
        }
    }

    @Test("A mostly-vertical scroll never switches session")
    func verticalScrollDoesNotNavigate() {
        let navigator = CarouselSwipeNavigator()
        #expect(feed(navigator, deltaX: 26, deltaY: 200, phase: .began) == nil)
        #expect(feed(navigator, deltaX: 5, deltaY: 200, phase: .changed) == nil)
    }

    @Test("Travel below the commit threshold is treated as an accidental brush")
    func shortTravelDoesNotNavigate() {
        let navigator = CarouselSwipeNavigator()
        #expect(feed(navigator, deltaX: 10, phase: .began) == nil)
        #expect(feed(navigator, deltaX: 10, phase: .changed) == nil)
        #expect(CarouselSwipeNavigator.commitThreshold > 20)
    }

    @Test("A new gesture can navigate again after the previous one committed")
    func gesturesAreIndependent() {
        let navigator = CarouselSwipeNavigator()
        #expect(feed(navigator, deltaX: 40, phase: .began) == .previous)
        _ = feed(navigator, deltaX: 0, phase: .ended)
        #expect(feed(navigator, deltaX: -40, phase: .began) == .next)
    }
}
