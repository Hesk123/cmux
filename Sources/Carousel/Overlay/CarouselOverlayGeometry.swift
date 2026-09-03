// Modified 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 37-40, 67-68, 77-83, 123.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import CoreGraphics

/// Everything the grid, the selection ring and the toast need to know about the
/// carousel's geometry.
///
/// U6 owns this type deliberately. It names only what the overlay layer
/// consumes, so grid and toast code compiles and is measurable before U1's
/// `CarouselGeometryProviding` lands, and it introduces no symbol U1 owns —
/// there is nothing here to conflict at merge. At integration U1 supplies one
/// of these in a single expression; see MAKER-U6.md, section Integration.
struct CarouselOverlayGeometry: Equatable {
    /// The reference video's viewport width. Every CSS-px figure in CONTRACT is
    /// quoted at this width and asserted as a ratio of it (ruling D-6), so a
    /// window of any other width rescales rather than voiding the row.
    static let referenceWidth: CGFloat = 1_344

    /// Logical viewport, in points, top-left origin.
    var viewport: CGSize

    /// The centred carousel card's rest rect, in viewport coordinates.
    /// CONTRACT rows 20 and 22: 0.720 W wide, 0.566 W tall, centred
    /// horizontally, centre y 20 CSS above the viewport's optical centre.
    var centreCardRect: CGRect

    /// The centred card's corner radius, in points. CONTRACT row 27, 0.0194 W.
    var cardCornerRadius: CGFloat

    init(viewport: CGSize, centreCardRect: CGRect, cardCornerRadius: CGFloat) {
        self.viewport = viewport
        self.centreCardRect = centreCardRect
        self.cardCornerRadius = cardCornerRadius
    }

    /// The contract's geometry at the reference width, for tests and for the
    /// stand-in the overlay uses until U1 lands.
    static func contractDefault(viewport: CGSize = CGSize(width: 1_344, height: 1_080)) -> CarouselOverlayGeometry {
        let cardWidth = viewport.width * 0.720
        let cardHeight = viewport.width * 0.566
        let centreY = viewport.height / 2 - viewport.width * 20 / referenceWidth
        return CarouselOverlayGeometry(
            viewport: viewport,
            centreCardRect: CGRect(
                x: (viewport.width - cardWidth) / 2,
                y: centreY - cardHeight / 2,
                width: cardWidth,
                height: cardHeight
            ),
            cardCornerRadius: viewport.width * 0.0194
        )
    }

    /// Rescales a figure measured at `referenceWidth` onto this viewport (D-6).
    /// Vertical figures use the same anchor, because the reference viewport's
    /// aspect is held.
    func scaled(_ valueAtReferenceWidth: CGFloat) -> CGFloat {
        valueAtReferenceWidth * viewport.width / Self.referenceWidth
    }

    /// Width divided by height. CONTRACT row 19 asserts 1.272 +/- 0.01.
    var cardAspect: CGFloat {
        guard centreCardRect.height > 0 else { return 0 }
        return centreCardRect.width / centreCardRect.height
    }

    /// CONTRACT row 37 (L21), **corrected by the orchestrator's measurement of
    /// 2026-09-03**: the height, the top edge and the right edge are fixed; the
    /// **width is content-dependent**. Two frames with the same top and the same
    /// right edge at device x = 2653 measured 530.8 and 447.7 device wide —
    /// 265.4 and 223.9 CSS. Row 37's single 0.225 W figure was one frame's
    /// content, not a constant, so it is kept as the **maximum** width and the
    /// natural width comes from the text.
    ///
    /// The top edge: row 37 says 24 CSS below the macOS menu bar, and the menu
    /// bar occupies the first 29 CSS of the reference viewport, so 53 CSS from
    /// the viewport top. D-8's arithmetic fixes the same number independently —
    /// it puts the card's top edge at 139.6 and requires the toast to clear it
    /// by 16.6, so the bottom edge is 123.0 and 123.0 - 70.02 = 52.98. The two
    /// readings agree to a third of a pixel.
    var toastHeight: CGFloat { scaled(70.02) }
    var toastTop: CGFloat { scaled(53) }
    var toastRightMargin: CGFloat { scaled(16) }
    /// Row 37's 0.225 W, now a ceiling rather than a fixed width.
    var toastMaxWidth: CGFloat { scaled(302.4) }
    /// A floor, so a two-word toast is a pill rather than a stub. Below both
    /// measured widths, so it never binds on real content.
    var toastMinWidth: CGFloat { scaled(215) }

    /// The pill anchored top-right at `width`, clamped to the cap and the floor.
    func toastRect(width: CGFloat) -> CGRect {
        let clamped = min(max(width, toastMinWidth), toastMaxWidth)
        return CGRect(
            x: viewport.width - toastRightMargin - clamped,
            y: toastTop,
            width: clamped,
            height: toastHeight
        )
    }

    /// The widest the pill can be, for clearance arithmetic that must hold in
    /// the worst case rather than for one string.
    var toastWidestRect: CGRect { toastRect(width: toastMaxWidth) }

    /// CONTRACT row 70: the toast reuses the prompt bar's radius token
    /// (0.0164 W = 22 CSS). No fourth radius is introduced.
    var toastCornerRadius: CGFloat { scaled(22) }

    /// The vertical band the grid block may occupy: below the toast, above the
    /// prompt bar. Used only when more sessions exist than the 3 x 2 grid holds
    /// and the block would otherwise overflow.
    var overlaySafeBand: ClosedRange<CGFloat> {
        let top = toastTop + toastHeight + scaled(12)
        let promptBarTop = viewport.height - scaled(34.5) - scaled(56.5)
        let bottom = promptBarTop - scaled(80)
        guard bottom > top else { return top...top }
        return top...bottom
    }
}
