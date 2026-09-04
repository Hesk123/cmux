// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import CoreGraphics
import Foundation

/// Every layout constant the carousel has, stated once.
///
/// CONTRACT rows 17-41, 69 and 123 quote CSS pixels at the reference capture's
/// 1344 x 1080 logical viewport. The contract's normalization rule makes each of
/// those a *ratio of the window's logical width* `W`, so a row keeps meaning at a
/// window the reference never had. Every ratio below is that rule applied once;
/// nothing outside this type may hardcode a layout pixel. A unit that types `968`
/// or `55` anywhere else has written a bug that only appears at a second window
/// size, which is exactly what row 20 exists to catch.
///
/// Coordinates are **CSS space**: origin top-left, `y` increasing downwards, in
/// logical points. That matches how every contract row and every VIDEO-REVIEW
/// measurement is written (`card spans y 139.6 -> 900.4`), so a test reads like the
/// row it is checking. `CarouselTrackView` converts to AppKit's bottom-left origin
/// at the one view boundary that needs it.
struct CarouselMetrics: Equatable, Sendable {
    /// The viewport every CSS-px figure in the contract is quoted at.
    static let referenceViewport = CGSize(width: 1344, height: 1080)

    // MARK: - Ratios (the contract, transcribed)

    /// Row 9 / row 20. 1:1 with the reference video's measured 0.631
    /// (Dawid's call, 2026-09-03 overnight: exact UI, no enlargement).
    /// An earlier revision carried 0.720 ("a little larger"); the shrunken
    /// flanks (9.9 % peek) hid the neighbouring sessions the reference shows
    /// at ~15.6 %, so the enlargement is deleted.
    static let cardWidthRatio: CGFloat = 0.631
    /// Row 19. Aspect preserved across the 1:1 restoration, which is what
    /// keeps row 20's second figure (0.496 * W tall) true without storing it
    /// twice.
    static let cardAspect: CGFloat = 1.272
    /// Row 23, restored to the video's own measured value by D-2.
    static let sideScale: CGFloat = 0.94
    /// Row 24 / D-13. Derived from the source's pitch formula, not copied from a
    /// suggestion: solving `w/2 + gap + (s*w)/2 = 878` at w = 848, s = 0.94 gives
    /// 55.44, and the video's own two gap measurements (57 and 54 CSS) bracket it.
    /// See ``sourceDerivedGap``, which recomputes it rather than asserting it.
    static let gapRatio: CGFloat = 0.0409
    /// Row 27, **corrected 2026-09-02**. VIDEO-REVIEW L11 reads 53 device px (26
    /// CSS) from a left-edge-per-row scan, but that method reads the point where
    /// the edge settles straight, which floors a radius rather than measuring it.
    /// U7 fitted a circle to all 60 arc rows at 0.48 px RMS and got **31 CSS**.
    /// The corner is also **circular**, not the `.continuous` squircle AppKit
    /// defaults to for a rounded rect - see `CarouselCardView.layout()`.
    /// Source: MAKER-U7 fit data.
    static let cornerRadiusRatio: CGFloat = 31.0 / 1344.0
    /// Row 22 / D-8. The card's vertical centre sits this far *above* the
    /// viewport's optical centre. The source used 57; D-8 cut it to 20 so the
    /// enlarged card clears the toast slot row 73 pins in place.
    static let verticalCentreOffsetRatio: CGFloat = 20.0 / 1344.0
    /// Row 54. The track-level recoil peak. U2 owns the curve; the value lives
    /// here because it is geometry, not timing.
    static let recoilScale: CGFloat = 0.971

    /// Row 31, the centre card's drag handle.
    static let dragHandleWidthRatio: CGFloat = 0.0290
    static let dragHandleHeightRatio: CGFloat = 0.0022
    static let dragHandleTopInsetRatio: CGFloat = 12.0 / 1344.0

    /// Row 42, the header's icon box.
    static let headerIconSideRatio: CGFloat = 26.0 / 1344.0

    /// Row 38. Grid card box and gutters.
    static let gridCardWidthRatio: CGFloat = 0.277
    static let gridCardHeightRatio: CGFloat = 0.217
    static let gridColumnGapRatio: CGFloat = 37.5 / 1344.0
    static let gridRowGapRatio: CGFloat = 39.0 / 1344.0
    static let gridColumns = 3
    static let gridRows = 2

    // MARK: - The only stored value

    /// Viewport in logical points. Everything else derives from it.
    var viewport: CGSize

    init(viewport: CGSize) {
        self.viewport = viewport
    }

    /// The window's logical width, which every ratio above is taken against.
    var width: CGFloat { viewport.width }
    var height: CGFloat { viewport.height }

    // MARK: - Carousel geometry

    /// Row 9 / row 20.
    var cardWidth: CGFloat { Self.cardWidthRatio * width }
    /// Row 19 and row 20's second figure, derived so the two can never disagree.
    var cardHeight: CGFloat { cardWidth / Self.cardAspect }
    var cardSize: CGSize { CGSize(width: cardWidth, height: cardHeight) }
    /// Row 24.
    var gap: CGFloat { Self.gapRatio * width }
    /// Row 27.
    var cornerRadius: CGFloat { Self.cornerRadiusRatio * width }

    /// Row 25. The source's own convention, not `width + gap`: adjacent centres sit
    /// half a full card plus a gap plus half a *scaled* card apart. At source
    /// geometry the naive form gives 903 against the measured 878 and is wrong by
    /// 25 CSS, which is more than twelve times the row's tolerance.
    var pitch: CGFloat {
        cardWidth / 2 + gap + (Self.sideScale * cardWidth) / 2
    }

    /// Row 21 / row 22. The centre every card shares, in CSS space.
    var cardCentre: CGPoint {
        CGPoint(
            x: width / 2,
            y: height / 2 - Self.verticalCentreOffsetRatio * width
        )
    }

    /// Row 10 / D-3. What a flank actually shows, computed rather than chosen:
    /// the width left over beside the centre card once both gaps are spent. The
    /// invented 20 % threshold an earlier revision carried is deleted.
    var visibleFlankWidth: CGFloat {
        (width - cardWidth - 2 * gap) / 2
    }

    /// Row 10's honest second figure: the fraction of its *own* width a flank
    /// shows. 0.242 at 1:1 geometry: the neighbouring sessions read clearly,
    /// which is the point of the peek.
    var visibleFlankFraction: CGFloat {
        let flankWidth = Self.sideScale * cardWidth
        guard flankWidth > 0 else { return 0 }
        return visibleFlankWidth / flankWidth
    }

    /// The rendered size of a card `slot` steps from centre. Row 23: flanks are
    /// scaled about the shared vertical centre, so the scale applies to both axes
    /// and the centre y is untouched.
    func size(forSlot slot: Int) -> CGSize {
        let scale = slot == 0 ? 1.0 : Self.sideScale
        return CGSize(width: cardWidth * scale, height: cardHeight * scale)
    }

    /// The rect of the card `slot` steps from centre, at rest, in CSS space.
    /// Negative is left. Rows 20, 21, 22, 23, 25.
    func rect(forSlot slot: Int) -> CGRect {
        let size = size(forSlot: slot)
        let centre = cardCentre
        return CGRect(
            x: centre.x + CGFloat(slot) * pitch - size.width / 2,
            y: centre.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Row 123's two card-side clearances, exposed so U5 and U6 assert against the
    /// same numbers rather than recomputing them.
    var cardTop: CGFloat { rect(forSlot: 0).minY }
    var cardBottom: CGFloat { rect(forSlot: 0).maxY }

    // MARK: - Grid geometry (row 38-40; U6 renders, this type measures)

    var gridCardSize: CGSize {
        CGSize(
            width: Self.gridCardWidthRatio * width,
            height: Self.gridCardHeightRatio * width
        )
    }

    var gridColumnGap: CGFloat { Self.gridColumnGapRatio * width }
    var gridRowGap: CGFloat { Self.gridRowGapRatio * width }

    var gridBlockSize: CGSize {
        let card = gridCardSize
        return CGSize(
            width: CGFloat(Self.gridColumns) * card.width
                + CGFloat(Self.gridColumns - 1) * gridColumnGap,
            height: CGFloat(Self.gridRows) * card.height
                + CGFloat(Self.gridRows - 1) * gridRowGap
        )
    }

    /// Row 38's side margin, derived from the block rather than stored, so the six
    /// values in that row cannot drift apart.
    var gridSideMargin: CGFloat { (width - gridBlockSize.width) / 2 }

    /// Row 39. The grid block and the carousel card row share one vertical centre,
    /// which is what makes row 77's shared-element transition mostly free.
    var gridBlockRect: CGRect {
        let size = gridBlockSize
        return CGRect(
            x: gridSideMargin,
            y: cardCentre.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Row 38. Grid slot `index`, reading left-to-right then top-to-bottom.
    func gridRect(forSlot index: Int) -> CGRect {
        let card = gridCardSize
        let block = gridBlockRect
        let column = index % Self.gridColumns
        let row = index / Self.gridColumns
        return CGRect(
            x: block.minX + CGFloat(column) * (card.width + gridColumnGap),
            y: block.minY + CGFloat(row) * (card.height + gridRowGap),
            width: card.width,
            height: card.height
        )
    }

    // MARK: - Card chrome boxes

    /// Row 31. Centre card only; `rect(forSlot:)` is the caller's job to pass.
    func dragHandleRect(inCardRect cardRect: CGRect) -> CGRect {
        let handleWidth = Self.dragHandleWidthRatio * width
        let handleHeight = Self.dragHandleHeightRatio * width
        return CGRect(
            x: cardRect.midX - handleWidth / 2,
            y: cardRect.minY + Self.dragHandleTopInsetRatio * width,
            width: handleWidth,
            height: handleHeight
        )
    }

    /// Row 42's icon box.
    var headerIconSide: CGFloat { Self.headerIconSideRatio * width }

    // MARK: - Typography (row 42, 45, 47)

    /// Point sizes are **not** pure ratios of `W`, and that is deliberate.
    ///
    /// The normalization rule exists so a *geometry* row survives a resize. Applied
    /// to type it would render 7.8 pt labels in a 700 pt window, which fails both
    /// the HIG legibility floor and row 16's design bar. Type therefore scales with
    /// the window but is clamped to [0.85x, 1.5x] of its reference size. At the
    /// fidelity window W = 1344 the clamp is inactive and the resolved size equals
    /// the contract's figure exactly, so rows 42, 45 and 47 assert unchanged.
    func scaledFontSize(_ referencePoints: CGFloat) -> CGFloat {
        let scale = width / Self.referenceViewport.width
        return referencePoints * min(max(scale, 0.85), 1.5)
    }

    /// Row 42: app name.
    var headerNameFontSize: CGFloat { scaledFontSize(15) }
    /// Row 42: dimmed second line.
    var headerSubtitleFontSize: CGFloat { scaledFontSize(12.5) }
    /// Row 43: status pill text.
    var statusPillFontSize: CGFloat { scaledFontSize(12.5) }
    /// Row 47: the three footer signal chips.
    var footerChipFontSize: CGFloat { scaledFontSize(12.5) }

    // MARK: - Slot occupancy (rows 26, 51, 57, 116)

    /// Which slots are rendered at `sessionCount` live sessions.
    ///
    /// Row 26 wants exactly three cards intersecting the viewport, and says so only
    /// at three or more sessions. Row 116 owns the rest and is the common case:
    /// zero renders the empty state, one renders a single centred card with no
    /// flank, two render one flank and wrap between the pair. At two sessions
    /// modular indexing would map slot -1 and slot +1 to the *same* session and
    /// draw it twice, so the pair case is named rather than left to the modulo.
    static func visibleSlots(forSessionCount sessionCount: Int) -> [Int] {
        switch sessionCount {
        case ..<1: return []
        case 1: return [0]
        case 2: return [0, 1]
        default: return [-1, 0, 1]
        }
    }

    /// The session index shown at `slot` when `centre` is centred. Rows 51 and 57:
    /// the carousel wraps, it never clamps, so this is modular and has no edge.
    static func sessionIndex(forSlot slot: Int, centre: Int, sessionCount: Int) -> Int? {
        guard sessionCount > 0 else { return nil }
        let raw = (centre + slot) % sessionCount
        return raw < 0 ? raw + sessionCount : raw
    }

    // MARK: - Provenance

    /// Recomputes D-13's derivation from the *source's* measured geometry rather
    /// than restating its result: `pitch = w/2 + gap + (s*w)/2` at the video's
    /// w = 848, s = 0.94 and measured pitch = 878. Returns 55.44.
    ///
    /// Row 24 and row 69 both require U1 to verify this rather than adopt it, and a
    /// test that recomputes it is the only form of that check which stays true when
    /// someone edits ``gapRatio``.
    static var sourceDerivedGap: CGFloat {
        let sourceCardWidth: CGFloat = 848
        let sourcePitch: CGFloat = 878
        return sourcePitch - sourceCardWidth / 2 - (sideScale * sourceCardWidth) / 2
    }
}
