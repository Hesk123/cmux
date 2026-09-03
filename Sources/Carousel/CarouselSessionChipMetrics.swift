// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import AppKit

/// Session-chip sizing, CONTRACT row 35: icon plus a ~13 CSS label, and the
/// pill's width **fits the label** rather than sitting at a fixed width.
///
/// The width is computed from a real text measurement, so a build that pinned
/// the chip to a constant fails the row rather than passing it by coincidence.
struct CarouselSessionChipMetrics: Equatable {
    static let referenceWindowWidth = CarouselPromptBarMetrics.referenceWindowWidth

    /// Row 35's "~13 CSS" label, expressed as a ratio so it scales with W.
    static let labelPointSizeRatio: Double = 13 / referenceWindowWidth
    static let iconSideRatio: Double = 15 / referenceWindowWidth
    static let iconLabelSpacingRatio: Double = 5 / referenceWindowWidth
    static let horizontalPaddingRatio: Double = 8 / referenceWindowWidth
    static let heightRatio: Double = 24 / referenceWindowWidth

    let windowWidth: Double

    init(windowWidth: Double) {
        self.windowWidth = windowWidth
    }

    var labelPointSize: Double { Self.labelPointSizeRatio * windowWidth }
    var iconSide: Double { Self.iconSideRatio * windowWidth }
    var iconLabelSpacing: Double { Self.iconLabelSpacingRatio * windowWidth }
    var horizontalPadding: Double { Self.horizontalPaddingRatio * windowWidth }
    var height: Double { Self.heightRatio * windowWidth }

    var labelFont: NSFont {
        .systemFont(ofSize: labelPointSize, weight: .medium)
    }

    /// Width of the rendered label alone.
    func labelWidth(for label: String) -> Double {
        let attributed = NSAttributedString(
            string: label,
            attributes: [.font: labelFont]
        )
        return Double(ceil(attributed.size().width))
    }

    /// Row 35: the pill hugs its label. Chip width is label width plus the
    /// fixed chrome, so two labels of different lengths give two widths.
    func chipWidth(for label: String) -> Double {
        horizontalPadding
            + iconSide
            + iconLabelSpacing
            + labelWidth(for: label)
            + horizontalPadding
    }

    /// The chrome the chip adds around its label — the constant row 35's
    /// "hugs its label within ±6 CSS px" tolerance is measured against.
    var chromeWidth: Double {
        horizontalPadding * 2 + iconSide + iconLabelSpacing
    }
}
