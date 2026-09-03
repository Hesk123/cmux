// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-03 for the cmux carousel UI (unit U1: row 28 capture-and-restore).

import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Row 28: the carousel-mode window flip and its restore. CRITIC-U1 F-6: the
/// capture-and-restore behaviour, including the already-non-opaque case the
/// ruling was written for, previously had no test at any level.
@MainActor
@Suite("Carousel mode translucency")
struct CarouselModeStateTests {
    @Test("Entering carousel mode makes the window non-opaque and exit restores it")
    func entryAndExitRoundTrip() {
        let window = NSWindow()
        let wasOpaque = window.isOpaque
        let wasColor = window.backgroundColor
        CarouselModeState.applyTranslucency(true, to: window)
        #expect(window.isOpaque == false)
        #expect(window.backgroundColor?.isEqual(.clear) == true)
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(window.isOpaque == wasOpaque)
        #expect(window.backgroundColor?.isEqual(wasColor) == true)
    }

    @Test("A window that entered non-opaque is not restored to opaque")
    func alreadyNonOpaqueWindowRestoresNonOpaque() {
        let window = NSWindow()
        window.isOpaque = false
        window.backgroundColor = .clear
        CarouselModeState.applyTranslucency(true, to: window)
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(window.isOpaque == false)
    }

    @Test("Exiting without entering leaves the window alone")
    func exitWithoutEntryIsNoop() {
        let window = NSWindow()
        let wasOpaque = window.isOpaque
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(window.isOpaque == wasOpaque)
    }

    @Test("Nil window is a no-op")
    func nilWindowIsNoop() {
        CarouselModeState.applyTranslucency(true, to: nil)
        CarouselModeState.applyTranslucency(false, to: nil)
    }
}
