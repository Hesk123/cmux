// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT row 65 (input half) and VIDEO-REVIEW §2.4 / §2.5.
@Suite("Carousel send sequence")
struct CarouselSendSequenceTests {
    @Test("Row 65's send window is 165 ms with a 25 ms tolerance")
    func sendWindowBounds() {
        #expect(CarouselSendSequence.isWithinSendWindow(.milliseconds(165)))
        #expect(CarouselSendSequence.isWithinSendWindow(.milliseconds(140)))
        #expect(CarouselSendSequence.isWithinSendWindow(.milliseconds(190)))
        #expect(!CarouselSendSequence.isWithinSendWindow(.milliseconds(139)))
        #expect(!CarouselSendSequence.isWithinSendWindow(.milliseconds(191)))
    }

    @Test("The input clears exactly one frame after Return")
    func inputClearsOneFrameLater() {
        // Ruling D-6: the target panel has no ProMotion, so a frame is 1/60 s.
        // Pinned as the measured value, not as the constant's own name.
        #expect(CarouselSendSequence.inputClearDelay == .nanoseconds(16_666_667))
        #expect(CarouselSendSequence.inputClearDelay < CarouselSendSequence.sendWindow)
    }

    @Test("The button glyph crosses over in about 120 ms")
    func buttonMorphDuration() {
        // VIDEO-REVIEW §2.4: the morph and the revert are both ~120 ms, and
        // both sit inside row 65's send window rather than after it.
        #expect(CarouselSendSequence.buttonMorphDuration == CarouselSendSequence.buttonRevertDelay)
        #expect(CarouselSendSequence.buttonMorphDuration <= CarouselSendSequence.sendWindow)
    }

    @Test("The glyph follows emptiness and nothing else")
    func buttonModeFollowsEmptiness() {
        #expect(CarouselComposeButtonMode(isComposedLineEmpty: true) == .voice)
        #expect(CarouselComposeButtonMode(isComposedLineEmpty: false) == .send)
    }
}
