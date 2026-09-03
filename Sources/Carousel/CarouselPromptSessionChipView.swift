// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import SwiftUI

/// The session chip inside the prompt bar — CONTRACT row 35.
///
/// Names the centred session and follows it through every switch (row 6). The
/// pill's width comes from `CarouselSessionChipMetrics`, so it hugs the label
/// rather than sitting at a fixed width, and the width change is animated as a
/// layout animation rather than snapping (VIDEO-REVIEW §2.2).
struct CarouselPromptSessionChipView: View {
    let sessionName: String
    let windowWidth: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: CarouselSessionChipMetrics {
        CarouselSessionChipMetrics(windowWidth: windowWidth)
    }

    var body: some View {
        HStack(spacing: metrics.iconLabelSpacing) {
            Image(systemName: "terminal")
                .font(.system(size: metrics.labelPointSize))
                .frame(width: metrics.iconSide, height: metrics.iconSide)
                .accessibilityHidden(true)

            Text(sessionName)
                .font(.system(size: metrics.labelPointSize, weight: .medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(height: metrics.height)
        .background(CarouselPromptBarPalette.sessionChipFill, in: .capsule)
        // Row 113 / ruling on reduced motion: the width change cross-fades
        // instead of sliding when the user has asked for less motion.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.205), value: sessionName)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            String(
                localized: "carousel.promptBar.sessionChip.label",
                defaultValue: "Centred session: \(sessionName)"
            )
        )
        .accessibilityIdentifier(CarouselPromptBarAccessibility.sessionChip)
    }
}
