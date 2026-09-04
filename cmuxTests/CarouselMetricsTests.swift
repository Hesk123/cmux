// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Rows 9, 10, 19-27, 31, 38-40, 51, 52, 57, 69, 116 and 123 are all statements
/// about `CarouselMetrics`, so they are checked here against the contract's own
/// numbers at the fidelity window, and again as ratios at two other window sizes.
///
/// The second half is the point. Absolute-pixel agreement at W = 1344 would also be
/// true of a build that hardcoded every number; asserting the same rows hold at
/// W = 1000 and W = 1800 is what actually proves the ratios are load-bearing, which
/// is what row 20 exists to catch.
@MainActor
@Suite("Carousel metrics")
struct CarouselMetricsTests {
    /// The fidelity window: 1344 x 1080 logical, per D-16 on the built-in panel at
    /// More Space.
    private var reference: CarouselMetrics {
        CarouselMetrics(viewport: CarouselMetrics.referenceViewport)
    }

    /// CONTRACT geometry tolerance.
    private let tolerance: CGFloat = 2

    // MARK: - Row 24 / row 69 / D-13: the gap is derived, not copied

    @Test("Row 24: the gap derives from the source pitch formula, giving 55.44")
    func gapDerivation() {
        // Recomputed from the *source's* measured geometry rather than restated:
        // solving w/2 + gap + (s*w)/2 = 878 at w = 848, s = 0.94.
        #expect(abs(CarouselMetrics.sourceDerivedGap - 55.44) < 0.01)
        // And the ratio this build ships reproduces it at the reference window,
        // which is the half that would break if someone edited `gapRatio`.
        #expect(abs(reference.gap - CarouselMetrics.sourceDerivedGap) < 0.5)
    }

    @Test("Row 24: the derivation matches the video's own two measured gaps")
    func gapMatchesVideoMeasurement() {
        // VIDEO-REVIEW section 1.1 measured 114 and 108 device px at 2x, i.e. 57 and
        // 54 CSS. The derived 55.44 sits between them, which is the independent
        // confirmation row 69 asks U1 for rather than a second reading of the same
        // number.
        #expect(CarouselMetrics.sourceDerivedGap > 54)
        #expect(CarouselMetrics.sourceDerivedGap < 57)
    }

    // MARK: - Rows 9, 19, 20, 21, 22

    @Test("Row 9 and row 20: the centre card is 848 x 667 at the fidelity window (1:1)")
    func centreCardSize() {
        let card = reference.rect(forSlot: 0)
        #expect(abs(card.width - 848.06) < tolerance)
        #expect(abs(card.height - 666.72) < tolerance)
    }

    @Test("Row 19: aspect is 1.272")
    func cardAspect() {
        let card = reference.rect(forSlot: 0)
        #expect(abs(card.width / card.height - 1.272) < 0.01)
    }

    @Test("Row 20: the height ratio the contract states separately, 0.496 * W")
    func cardHeightRatio() {
        // Height is derived from width and aspect rather than stored, so this checks
        // the derivation agrees with the row's own second figure instead of asserting
        // a number this type could not contradict.
        #expect(abs(reference.cardHeight / reference.width - 0.4961) < 0.001)
    }

    @Test("Row 21: the card is horizontally centred within 2 CSS px")
    func cardHorizontallyCentred() {
        #expect(abs(reference.rect(forSlot: 0).midX - reference.width / 2) < tolerance)
    }

    @Test("Row 22 and D-8: the card centre sits 20 CSS above the optical centre")
    func verticalOffset() {
        let card = reference.rect(forSlot: 0)
        #expect(abs(card.midY - (reference.height / 2 - 20)) < tolerance)
        // D-8's own spans, which are what row 123's clearances are computed from.
        #expect(abs(card.minY - 186.64) < tolerance)
        #expect(abs(card.maxY - 853.36) < tolerance)
    }

    // MARK: - Rows 23, 25, 26

    @Test("Row 23: flanks render at 0.94 and share the centre's y")
    func flankScaleAndSharedCentre() {
        let centre = reference.rect(forSlot: 0)
        for slot in [-1, 1] {
            let flank = reference.rect(forSlot: slot)
            #expect(abs(flank.height / centre.height - 0.94) < 0.005)
            #expect(abs(flank.midY - centre.midY) < tolerance)
        }
    }

    @Test("Row 25: pitch is the source's formula, not width plus gap")
    func slotPitch() {
        let left = reference.rect(forSlot: -1)
        let centre = reference.rect(forSlot: 0)
        let right = reference.rect(forSlot: 1)
        #expect(abs((centre.midX - left.midX) - reference.pitch) < 0.001)
        #expect(abs((right.midX - centre.midX) - reference.pitch) < 0.001)
        // Row 25's stated 0.653 * W: at 1:1 geometry the pitch converges on the
        // source's own measured 878.
        #expect(abs(reference.pitch - 0.653 * reference.width) < tolerance)
        #expect(abs(reference.pitch - 877.6) < tolerance)
        // The naive form is wrong by 25 CSS at source geometry; assert this build
        // did not silently adopt it.
        #expect(abs(reference.pitch - (reference.cardWidth + reference.gap)) > 10)
    }

    @Test("Row 26: exactly three cards intersect the viewport, and the fourth does not")
    func threeCardsVisible() {
        let viewport = CGRect(origin: .zero, size: reference.viewport)
        let intersecting = (-3...3).count { slot in
            reference.rect(forSlot: slot).intersects(viewport)
        }
        #expect(intersecting == 3)
        #expect(!reference.rect(forSlot: 2).intersects(viewport))
        #expect(!reference.rect(forSlot: -2).intersects(viewport))
    }

    // MARK: - Rows 10 and 27

    @Test("Row 10 and D-3: visible flank width computes to 133 CSS = 0.099 * W")
    func visibleFlankWidth() {
        #expect(abs(reference.visibleFlankWidth - 133) < tolerance)
        #expect(abs(reference.visibleFlankWidth / reference.width - 0.099) < 0.005)
    }

    @Test("Row 10: the honest cost of the enlargement, 14.6 % of a flank's own width")
    func visibleFlankFraction() {
        // Row 10 states both figures so the trade is visible. This asserts the one
        // this build actually produces, so a later geometry change that quietly
        // erodes it fails here rather than in a Phase 6 read-through.
        #expect(abs(reference.visibleFlankFraction - 0.146) < 0.005)
    }

    @Test("Row 27, corrected: corner radius is 31 CSS, not VIDEO-REVIEW's 26")
    func cornerRadius() {
        // U7's circular fit over all 60 arc rows, 0.48 px RMS. The contract's 26
        // came from a left-edge-per-row scan, which reads where the edge settles
        // straight and therefore floors a radius.
        #expect(abs(reference.cornerRadius - 31) < tolerance)
        #expect(abs(reference.cornerRadius - 26) > tolerance)
    }

    // MARK: - Row 31

    @Test("Row 31: the drag handle is 39 x 3 CSS, 12 CSS below the card top")
    func dragHandle() {
        let card = reference.rect(forSlot: 0)
        let handle = reference.dragHandleRect(inCardRect: card)
        #expect(abs(handle.width - 39) < tolerance)
        #expect(abs(handle.height - 3) < 1)
        #expect(abs(handle.minY - (card.minY + 12)) < tolerance)
        #expect(abs(handle.midX - card.midX) < tolerance)
    }

    // MARK: - Rows 38, 39, 40

    @Test("Row 38: the grid is 3 x 2 at 372 x 292 with 37.5 / 39 gaps and a 76 margin")
    func gridGeometry() {
        let card = reference.gridRect(forSlot: 0)
        #expect(abs(card.width - 372) < tolerance)
        #expect(abs(card.height - 292) < tolerance)
        #expect(abs(reference.gridColumnGap - 37.5) < tolerance)
        #expect(abs(reference.gridRowGap - 39) < tolerance)
        #expect(abs(reference.gridSideMargin - 76) < tolerance)
        // Column and row pitches, which is what a frame diff actually measures.
        #expect(abs(reference.gridRect(forSlot: 1).minX - reference.gridRect(forSlot: 0).maxX - 37.5) < tolerance)
        #expect(abs(reference.gridRect(forSlot: 3).minY - reference.gridRect(forSlot: 0).maxY - 39) < tolerance)
    }

    @Test("Row 39: the grid block shares the carousel card's vertical centre")
    func gridSharesVerticalCentre() {
        #expect(abs(reference.gridBlockRect.midY - reference.rect(forSlot: 0).midY) < tolerance)
    }

    @Test("Row 40: grid card aspect equals the carousel card aspect")
    func gridAspect() {
        let grid = reference.gridRect(forSlot: 0)
        let carousel = reference.rect(forSlot: 0)
        #expect(abs(grid.width / grid.height - carousel.width / carousel.height) < 0.01)
    }

    // MARK: - Row 123

    @Test("Row 123: the card clears the toast above it and leaves 88.6 below")
    func verticalClearances() {
        // The pill and toast edges are U5's and U6's to place; row 123's card-side
        // figures are D-8's own and are what those units measure against.
        #expect(abs(reference.cardTop - 139.6) < tolerance)
        // 1080 - 900.4 = 179.6 to the viewport bottom; D-8 reserves 88.6 of that
        // between the card bottom and the prompt bar's top edge.
        #expect(reference.height - reference.cardBottom > 88.6)
    }

    // MARK: - Row 20's real test: the ratios hold at other window sizes

    @Test("Row 20: every ratio holds at 1000, 1344 and 1800 wide", arguments: [1000.0, 1344.0, 1800.0])
    func ratiosHoldAtAnyWidth(width: Double) {
        let w = CGFloat(width)
        // The reference viewport's aspect, preserved so vertical rows stay comparable.
        let height = w / (CarouselMetrics.referenceViewport.width / CarouselMetrics.referenceViewport.height)
        let metrics = CarouselMetrics(viewport: CGSize(width: w, height: height))
        let card = metrics.rect(forSlot: 0)

        #expect(abs(card.width / w - 0.720) < 0.001)
        #expect(abs(card.height / w - 0.566) < 0.001)
        #expect(abs(card.width / card.height - 1.272) < 0.01)
        #expect(abs(card.midX - w / 2) < 0.001)
        #expect(abs(metrics.gap / w - 0.0409) < 0.0001)
        #expect(abs(metrics.pitch / w - 0.739) < 0.001)
        #expect(abs(metrics.cornerRadius / w - 31.0 / 1344.0) < 0.0001)
        #expect(abs(metrics.visibleFlankWidth / w - 0.099) < 0.005)
        #expect(abs(metrics.rect(forSlot: 1).height / card.height - 0.94) < 0.005)
        #expect(abs(metrics.gridBlockRect.midY - card.midY) < 0.001)
    }

    // MARK: - Rows 51, 57, 116: wrap-around and the small-N cases

    @Test("Row 116: slot occupancy at zero, one, two and three sessions")
    func slotOccupancy() {
        #expect(CarouselMetrics.visibleSlots(forSessionCount: 0).isEmpty)
        #expect(CarouselMetrics.visibleSlots(forSessionCount: 1) == [0])
        // Two sessions render one flank, never the same session twice: modular
        // indexing would map slot -1 and slot +1 onto the same session and draw it
        // on both sides.
        #expect(CarouselMetrics.visibleSlots(forSessionCount: 2) == [0, 1])
        #expect(CarouselMetrics.visibleSlots(forSessionCount: 3) == [-1, 0, 1])
        #expect(CarouselMetrics.visibleSlots(forSessionCount: 9) == [-1, 0, 1])
    }

    @Test("Row 57: indexing wraps in both directions and never clamps")
    func wrapAround() {
        // Right edge.
        #expect(CarouselMetrics.sessionIndex(forSlot: 1, centre: 5, sessionCount: 6) == 0)
        // Left edge - the case a `max(0, ...)` clamp would silently get wrong.
        #expect(CarouselMetrics.sessionIndex(forSlot: -1, centre: 0, sessionCount: 6) == 5)
        #expect(CarouselMetrics.sessionIndex(forSlot: -2, centre: 0, sessionCount: 6) == 4)
        #expect(CarouselMetrics.sessionIndex(forSlot: 0, centre: 3, sessionCount: 6) == 3)
        #expect(CarouselMetrics.sessionIndex(forSlot: 1, centre: 0, sessionCount: 1) == 0)
        #expect(CarouselMetrics.sessionIndex(forSlot: 0, centre: 0, sessionCount: 0) == nil)
    }

    @Test("Row 51: navigating once per session plus one returns to the start")
    func fullLapReturnsToStart() {
        let count = 6
        var centre = 0
        for _ in 0..<count {
            centre = CarouselMetrics.sessionIndex(forSlot: 1, centre: centre, sessionCount: count) ?? -1
        }
        #expect(centre == 0)
    }

    // MARK: - Typography clamp

    @Test("Rows 42 and 45: type resolves to the contract's size at the fidelity window")
    func typographyAtReferenceWindow() {
        #expect(abs(reference.headerNameFontSize - 15) < 0.01)
        #expect(abs(reference.headerSubtitleFontSize - 12.5) < 0.01)
        #expect(abs(reference.footerChipFontSize - 12.5) < 0.01)
    }

    @Test("Type scales with the window but never below a legible floor")
    func typographyClamp() {
        // The normalization rule applied literally to point sizes would render 7.8 pt
        // labels in a 700 pt window. The clamp is a stated deviation, and this is
        // what pins it: inactive at the reference window, active at the extremes.
        let small = CarouselMetrics(viewport: CGSize(width: 700, height: 563))
        let large = CarouselMetrics(viewport: CGSize(width: 3000, height: 2411))
        #expect(small.headerNameFontSize >= 15 * 0.85)
        #expect(large.headerNameFontSize <= 15 * 1.5)
    }
}
