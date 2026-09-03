// Modified 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 38, 39, 40.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import CoreGraphics

/// The 3 x 2 overview grid. CONTRACT row 38: card 0.277 W x 0.217 W, gaps
/// 37.5 / 39 CSS, side margin 76 CSS; row 39: the block shares the carousel
/// card's vertical centre; row 40: the grid card's aspect equals the carousel
/// card's.
///
/// Two of those four figures are *derived* rather than copied, for the same
/// reason ruling D-3 derives the flank width and D-13 derives the gap — a
/// derived value stays correct when the geometry it depends on changes, and a
/// copied one silently stops matching:
///
/// * **Card height** is `cardWidth / carouselAspect`, not `0.217 * W`. Row 40
///   then holds exactly instead of by 0.0045, and the derived height is 292.6
///   CSS against row 38's measured 291.6 — inside H1's +/- 2 CSS.
/// * **Side margin** is `(W - blockWidth) / 2`, which computes to 76.07 CSS
///   against row 38's measured 76, and cannot drift out of symmetry.
///
/// One measured figure does *not* survive Dawid's larger card, and it is
/// recorded rather than engineered away: VIDEO-REVIEW section 1.7 measured the
/// grid card at 0.438 of the carousel card. Row 9 enlarged the carousel card to
/// 0.720 W while row 38 pinned the grid card at 0.277 W, so the effective scale
/// here is **0.385**, and 0.438 would need a 1347-CSS block in a 1344-CSS
/// viewport. Row 38 is the locked target; 0.438 is not reachable alongside
/// row 9 and is not a separate assertion.
struct CarouselGridLayout: Equatable {
    static let columns = 3
    static let preferredRows = 2
    /// The reference has exactly six sessions and a 3 x 2 grid.
    static let preferredCapacity = columns * preferredRows

    /// The number of cards this layout was built for.
    let count: Int
    let rows: Int
    let cardSize: CGSize
    let columnGap: CGFloat
    let rowGap: CGFloat
    /// The block's own bounds in viewport coordinates, top-left origin.
    let blockRect: CGRect
    /// Uniform scale applied to the whole block when more cards exist than the
    /// preferred 3 x 2 and the natural block would leave the safe band. 1.0 in
    /// every asserted case.
    let overflowScale: CGFloat

    var sideMargin: CGFloat { blockRect.minX }

    init(geometry: CarouselOverlayGeometry, count: Int = CarouselGridLayout.preferredCapacity) {
        let clampedCount = max(count, 1)
        self.count = clampedCount

        let columns = CGFloat(Self.columns)
        let rowCount = max(1, Int((Double(clampedCount) / Double(Self.columns)).rounded(.up)))
        self.rows = rowCount

        let naturalCardWidth = geometry.viewport.width * 0.277
        let aspect = geometry.cardAspect > 0 ? geometry.cardAspect : 1.272
        let naturalCardHeight = naturalCardWidth / aspect
        let naturalColumnGap = geometry.scaled(37.5)
        let naturalRowGap = geometry.scaled(39)

        let naturalBlockHeight = naturalCardHeight * CGFloat(rowCount) + naturalRowGap * CGFloat(rowCount - 1)

        // Only bites above six cards, which is beyond every asserted row. Keeps
        // the block inside the band between the toast and the prompt bar rather
        // than letting it grow under either.
        let band = geometry.overlaySafeBand
        let available = band.upperBound - band.lowerBound
        let scale: CGFloat = (naturalBlockHeight > available && available > 0)
            ? available / naturalBlockHeight
            : 1
        self.overflowScale = scale

        self.cardSize = CGSize(width: naturalCardWidth * scale, height: naturalCardHeight * scale)
        self.columnGap = naturalColumnGap * scale
        self.rowGap = naturalRowGap * scale

        let blockWidth = cardSize.width * columns + self.columnGap * (columns - 1)
        let blockHeight = cardSize.height * CGFloat(rowCount) + self.rowGap * CGFloat(rowCount - 1)
        // Row 39: the block's vertical centre is the carousel card's, exactly.
        let centreY = geometry.centreCardRect.midY
        self.blockRect = CGRect(
            x: (geometry.viewport.width - blockWidth) / 2,
            y: centreY - blockHeight / 2,
            width: blockWidth,
            height: blockHeight
        )
    }

    /// Row-major, matching the reference's reading order and CONTRACT row 51's
    /// stable carousel order, so the grid and the carousel never disagree about
    /// which session is which.
    func rect(forSlot index: Int) -> CGRect {
        let column = index % Self.columns
        let row = index / Self.columns
        return CGRect(
            x: blockRect.minX + CGFloat(column) * (cardSize.width + columnGap),
            y: blockRect.minY + CGFloat(row) * (cardSize.height + rowGap),
            width: cardSize.width,
            height: cardSize.height
        )
    }

    /// Scale of a grid card against the centred carousel card.
    func cardScale(against geometry: CarouselOverlayGeometry) -> CGFloat {
        guard geometry.centreCardRect.width > 0 else { return 0 }
        return cardSize.width / geometry.centreCardRect.width
    }

    var cardAspect: CGFloat {
        guard cardSize.height > 0 else { return 0 }
        return cardSize.width / cardSize.height
    }
}
