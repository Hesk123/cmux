import AppKit
import CmuxFoundation
import SwiftUI

/// Every visual constant the sub-agents chip and popover use, in one place.
///
/// Two reasons it is a value type rather than literals in the views. First,
/// Dawid has not picked a chrome direction yet, so the placement and skin will
/// be restyled once from his pick and the views must not need touching for it.
/// Second, fidelity is asserted as ratios of the window width, not absolutes:
/// every measurement below is `value × W / 1344`, anchored to the reference
/// video's 1344-wide viewport, so the layout survives a resize (CONTRACT
/// normalization rule, D-6).
///
/// The colours and type sizes are not new tokens. CONTRACT row 70 allows an
/// addition to reuse the prompt bar (`#0B151D`, radius 0.0164 · W), the session
/// chip (`#262E37`, 13 CSS) or the status pill's treatment (dark translucent,
/// fully rounded, 12.5 CSS), and nothing here steps outside those three. The
/// popover's 26 CSS corner is the card's own radius (row 27), which
/// VIDEO-REVIEW § 6.B specifies for this panel — an existing token, not a
/// fourth one.
struct SubAgentsPresentation: Sendable, Equatable {
    /// The window width the ratios are applied to.
    var width: CGFloat

    /// The reference video's logical viewport width. Every CSS figure quoted in
    /// this file is quoted at this width.
    static let referenceWidth: CGFloat = 1344

    static let chipFillHex = "262E37"
    static let popoverFillHex = "0B151D"

    static func standard(width: CGFloat) -> SubAgentsPresentation {
        SubAgentsPresentation(width: width)
    }

    private func scaled(_ css: CGFloat) -> CGFloat {
        css * width / Self.referenceWidth
    }

    // MARK: - Chip (status-pill treatment)

    var chipLabelSize: CGFloat { scaled(12.5) }
    var chipIconSize: CGFloat { scaled(12) }
    var chipHorizontalPadding: CGFloat { scaled(10) }
    var chipVerticalPadding: CGFloat { scaled(4.5) }
    var chipSpacing: CGFloat { scaled(5) }
    var chipFill: Color { Self.color(hex: Self.chipFillHex, fallback: .black) }

    // MARK: - Popover

    var popoverWidth: CGFloat { scaled(300) }
    var popoverMaxHeight: CGFloat { scaled(360) }
    /// The card's radius (CONTRACT row 27, 0.0194 · W), per VIDEO-REVIEW § 6.B.
    var popoverCornerRadius: CGFloat { scaled(26) }
    var popoverPadding: CGFloat { scaled(14) }
    var popoverFill: Color { Self.color(hex: Self.popoverFillHex, fallback: .black) }
    /// Vertical gap between the chip and the panel it opens. Kept under
    /// CONTRACT row 72's 8 px anchor tolerance.
    var popoverAnchorGap: CGFloat { scaled(6) }

    var rowSpacing: CGFloat { scaled(10) }
    var rowTitleSize: CGFloat { scaled(13) }
    var rowSubtitleSize: CGFloat { scaled(12.5) }
    var rowIndent: CGFloat { scaled(14) }
    var statusDotSize: CGFloat { scaled(7) }

    // MARK: - Motion

    /// CONTRACT row 72: the panel scales in from the chip over ~180 ms with an
    /// ease-out, and a fade-only open fails the row.
    static let openDuration: TimeInterval = 0.18
    /// Below row 72's 0.9 ceiling, and far from zero — nothing in the real
    /// world appears out of nothing.
    static let openInitialScale: CGFloat = 0.88
    /// Reduced motion keeps the fade and drops the movement, which is the
    /// gentler equivalent rather than no feedback at all.
    static let reducedMotionDuration: TimeInterval = 0.12

    static func openAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: reducedMotionDuration)
            : .timingCurve(0.23, 1, 0.32, 1, duration: openDuration)
    }

    private static func color(hex: String, fallback: Color) -> Color {
        guard let nsColor = NSColor(hex: hex) else { return fallback }
        return Color(nsColor: nsColor)
    }
}
