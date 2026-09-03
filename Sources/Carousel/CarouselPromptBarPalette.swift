// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import SwiftUI

/// The prompt bar's sampled colours, CONTRACT rows 32 and 35.
///
/// Held as 8-bit components so the H1 frame-diff can compare against the same
/// numbers it samples out of `video/hi/rest.png`, rather than against a
/// `Color` whose components would have to be read back through a colour space.
enum CarouselPromptBarPalette {
    /// Row 32: bar fill `#0B151D`, rendered translucent over the card layer.
    static let barFillComponents: (red: Int, green: Int, blue: Int) = (11, 21, 29)
    static let barFillOpacity: Double = 0.86

    /// Row 35: session chip fill `#262E37`.
    static let sessionChipFillComponents: (red: Int, green: Int, blue: Int) = (38, 46, 55)

    static var barFill: Color { color(barFillComponents).opacity(barFillOpacity) }
    static var sessionChipFill: Color { color(sessionChipFillComponents) }

    /// Row 34: the action button is blue and never changes colour, size or
    /// position across the voice/send morph (VIDEO-REVIEW §2.4).
    static let actionButtonFill = Color.accentColor

    private static func color(_ components: (red: Int, green: Int, blue: Int)) -> Color {
        Color(
            .sRGB,
            red: Double(components.red) / 255,
            green: Double(components.green) / 255,
            blue: Double(components.blue) / 255,
            opacity: 1
        )
    }
}
