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
@Suite("Carousel mode translucency", .serialized)
struct CarouselModeStateTests {
    @Test("Entering carousel mode makes the window non-opaque and exit restores it")
    func entryAndExitRoundTrip() {
        let window = NSWindow()
        let wasOpaque = window.isOpaque
        let wasColor = window.backgroundColor
        CarouselModeState.applyTranslucency(true, to: window)
        #expect(window.isOpaque == false)
        #expect(window.backgroundColor?.isEqual(NSColor.clear) == true)
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

    @Test("Entering carousel mode hides title and traffic lights, exit restores them")
    func chromeHiddenAndRestored() {
        let window = NSWindow()
        window.orderBack(nil)
        defer { window.close() }
        let wasTitle = window.titleVisibility
        CarouselModeState.applyTranslucency(true, to: window)
        #expect(window.titleVisibility == .hidden)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(window.titleVisibility == wasTitle)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == false)
    }

    @Test("Entering carousel mode requests fullscreen once, exit restores only what it entered")
    func fullscreenEnterAndRestore() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.orderBack(nil)
        var calls = 0
        CarouselModeState.fullscreenToggle = { win in if win === window { calls += 1 } }
        defer { CarouselModeState.fullscreenToggle = { win in win.toggleFullScreen(nil) } }
        CarouselModeState.applyTranslucency(true, to: window)
        #expect(calls == 1)
        CarouselModeState.applyTranslucency(true, to: window)
        #expect(calls == 1)
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(calls == 2)
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(calls == 2)
        window.close()
    }

    @Test("Already-fullscreen window is left alone")
    func fullscreenAlreadyThere() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.orderBack(nil)
        var calls = 0
        CarouselModeState.fullscreenToggle = { win in if win === window { calls += 1 } }
        defer { CarouselModeState.fullscreenToggle = { win in win.toggleFullScreen(nil) } }
        window.styleMask.insert(.fullScreen)
        CarouselModeState.applyTranslucency(true, to: window)
        CarouselModeState.applyTranslucency(false, to: window)
        #expect(calls == 0)
        window.close()
    }

    @Test("Nil window is a no-op")
    func nilWindowIsNoop() {
        CarouselModeState.applyTranslucency(true, to: nil)
        CarouselModeState.applyTranslucency(false, to: nil)
    }
}
