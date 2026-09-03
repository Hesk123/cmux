// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import SwiftUI

/// The blue circle at the trailing edge of the prompt bar — CONTRACT row 34,
/// VIDEO-REVIEW §1.4 and §2.4.
///
/// The circle never changes size, colour or position across the morph: only the
/// glyph crosses over, in ~120 ms. Fixing the frame and the fill outside the
/// mode switch is what makes that true structurally rather than by good luck.
struct CarouselComposeActionButton: View {
    let mode: CarouselComposeButtonMode
    let diameter: Double
    let reduceMotion: Bool
    let action: () -> Void

    private var glyph: String {
        mode == .voice ? "waveform" : "arrow.up"
    }

    private var label: String {
        mode == .voice
            ? String(localized: "carousel.promptBar.voice", defaultValue: "Dictate")
            : String(localized: "carousel.promptBar.send", defaultValue: "Send")
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .background(CarouselPromptBarPalette.actionButtonFill, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(CarouselPromptBarAccessibility.actionButton)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.120),
            value: mode
        )
    }
}
