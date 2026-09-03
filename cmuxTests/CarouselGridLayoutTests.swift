// Added 2026-09-02 for the cmux carousel UI build, unit U6.
// CONTRACT rows 37, 38, 39, 40, 73 (toast half), 123 (toast half).
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// H1-equivalent geometry assertions, done against the layout that produces the
/// pixels rather than against a screenshot of them. Every figure is checked at
/// the reference width **and** at two other widths, because ruling D-6 makes
/// each target a ratio of W and a row that only holds at 1344 is not asserted,
/// it is coincidental.
@MainActor
final class CarouselGridLayoutTests: XCTestCase {
    private let reference = CGSize(width: 1_344, height: 1_080)
    private let narrow = CGSize(width: 1_100, height: 884)
    private let wide = CGSize(width: 1_600, height: 1_286)

    private func geometry(_ size: CGSize) -> CarouselOverlayGeometry {
        CarouselOverlayGeometry.contractDefault(viewport: size)
    }

    /// H1 tolerance from the contract's harness section: +/- 2 CSS px on
    /// geometry, scaled onto the viewport under test.
    private func tolerance(_ g: CarouselOverlayGeometry) -> CGFloat { g.scaled(2) }

    // MARK: - Row 38 (L22)

    func testGridBlockMatchesRow38AtTheReferenceWidth() {
        let g = geometry(reference)
        let layout = CarouselGridLayout(geometry: g)

        XCTAssertEqual(layout.rows, 2)
        XCTAssertEqual(CarouselGridLayout.columns, 3)
        XCTAssertEqual(layout.cardSize.width, 372.288, accuracy: 2, "row 38 card width 0.277 W")
        XCTAssertEqual(layout.cardSize.height, 291.6, accuracy: 2, "row 38 card height 0.217 W")
        XCTAssertEqual(layout.columnGap, 37.5, accuracy: 2, "row 38 column gap")
        XCTAssertEqual(layout.rowGap, 39, accuracy: 2, "row 38 row gap")
        XCTAssertEqual(layout.sideMargin, 76, accuracy: 2, "row 38 side margin")
        XCTAssertEqual(layout.blockRect.width, 1_192, accuracy: 2, "VIDEO-REVIEW 1.7 block width")
        XCTAssertEqual(layout.blockRect.height, 623, accuracy: 2.5, "VIDEO-REVIEW 1.7 block height")
        XCTAssertEqual(layout.overflowScale, 1, accuracy: 0.0001, "no overflow scaling at six cards")
    }

    func testGridRatiosHoldAtEveryWindowWidth() {
        for size in [reference, narrow, wide] {
            let g = geometry(size)
            let layout = CarouselGridLayout(geometry: g)
            let tol = tolerance(g)
            XCTAssertEqual(layout.cardSize.width, size.width * 0.277, accuracy: tol,
                           "card width stays 0.277 W at \(size.width)")
            XCTAssertEqual(layout.columnGap, g.scaled(37.5), accuracy: tol,
                           "column gap stays a ratio of W at \(size.width)")
            XCTAssertEqual(layout.rowGap, g.scaled(39), accuracy: tol,
                           "row gap stays a ratio of W at \(size.width)")
            XCTAssertEqual(layout.sideMargin, g.scaled(76), accuracy: tol,
                           "side margin stays a ratio of W at \(size.width)")
        }
    }

    func testGridSlotsAreRowMajorAndEvenlyPitched() {
        let g = geometry(reference)
        let layout = CarouselGridLayout(geometry: g)
        let rects = (0..<6).map { layout.rect(forSlot: $0) }

        // Row-major: the first three share a top edge, the last three share a
        // lower one, and columns line up across rows.
        XCTAssertEqual(rects[0].minY, rects[1].minY, accuracy: 0.001)
        XCTAssertEqual(rects[1].minY, rects[2].minY, accuracy: 0.001)
        XCTAssertEqual(rects[3].minY, rects[5].minY, accuracy: 0.001)
        XCTAssertEqual(rects[0].minX, rects[3].minX, accuracy: 0.001)
        XCTAssertEqual(rects[2].minX, rects[5].minX, accuracy: 0.001)

        let columnPitch = rects[1].minX - rects[0].minX
        XCTAssertEqual(rects[2].minX - rects[1].minX, columnPitch, accuracy: 0.001)
        XCTAssertEqual(columnPitch, layout.cardSize.width + layout.columnGap, accuracy: 0.001)
        XCTAssertEqual(rects[3].minY - rects[0].minY,
                       layout.cardSize.height + layout.rowGap, accuracy: 0.001)

        // The block is symmetric in the viewport: the margin on the right
        // equals the margin on the left. Row 38 states one number; asserting
        // both is what makes an off-centre block fail.
        XCTAssertEqual(reference.width - rects[2].maxX, rects[0].minX, accuracy: 0.001)
    }

    // MARK: - Row 39 (L23)

    func testGridBlockSharesTheCarouselCardVerticalCentre() {
        for size in [reference, narrow, wide] {
            let g = geometry(size)
            let layout = CarouselGridLayout(geometry: g)
            XCTAssertEqual(layout.blockRect.midY, g.centreCardRect.midY, accuracy: tolerance(g),
                           "row 39: shared vertical centre at \(size.width)")
        }
    }

    func testGridBlockKeepsTheSharedCentreBelowSixCards() {
        // Row 116 defines 0, 1 and 2 sessions for the carousel; the grid must
        // not lose row 39 at those counts either. One row of cards is still
        // centred on the carousel card's centre.
        let g = geometry(reference)
        for count in 1...6 {
            let layout = CarouselGridLayout(geometry: g, count: count)
            XCTAssertEqual(layout.blockRect.midY, g.centreCardRect.midY, accuracy: tolerance(g),
                           "row 39 holds at \(count) cards")
            XCTAssertEqual(layout.rows, count <= 3 ? 1 : 2, "rows at \(count) cards")
        }
    }

    // MARK: - Row 40 (L24)

    func testGridCardAspectEqualsCarouselCardAspect() {
        for size in [reference, narrow, wide] {
            let g = geometry(size)
            let layout = CarouselGridLayout(geometry: g)
            XCTAssertEqual(layout.cardAspect, g.cardAspect, accuracy: 0.01,
                           "row 40: within 0.01 of the carousel aspect at \(size.width)")
            // Row 19's own value, so the chain card -> grid card is pinned to
            // the measured number and not merely internally consistent.
            XCTAssertEqual(layout.cardAspect, 1.272, accuracy: 0.01, "row 19 aspect")
        }
    }

    func testGridCardScaleAgainstTheEnlargedCarouselCardIsRecorded() {
        // VIDEO-REVIEW 1.7 measured 0.438 against the source's 848-CSS card.
        // Row 9 enlarged the card to 0.720 W, so the reachable scale is 0.385.
        // Asserting the real number keeps the deviation visible instead of
        // letting a later reader treat 0.438 as a missed target.
        let g = geometry(reference)
        let layout = CarouselGridLayout(geometry: g)
        XCTAssertEqual(layout.cardScale(against: g), 0.385, accuracy: 0.005)
        // And 0.438 genuinely does not fit, which is why it was not chosen.
        let atSourceScale = g.centreCardRect.width * 0.438 * 3 + 2 * g.scaled(37.5)
        XCTAssertGreaterThan(atSourceScale, reference.width,
                             "a 0.438 grid overflows the viewport at row 9's card width")
    }

    // MARK: - Row 37 (L21) and row 123's toast half

    func testToastGeometryMatchesRow37() {
        // Row 37 corrected by the orchestrator's 2026-09-03 measurement: the
        // height, the top edge and the right edge are fixed; the width is
        // content-dependent and 0.225 W is its ceiling. Two source frames with
        // the same top and the same right edge measured 530.8 and 447.7 device
        // wide, so a fixed-width assertion here would enforce a number the
        // source itself does not hold to.
        let g = geometry(reference)
        XCTAssertEqual(g.toastHeight, reference.width * 0.0521, accuracy: 2, "row 37 height 0.0521 W")
        XCTAssertEqual(g.toastHeight, 70.02, accuracy: 0.5, "70 CSS, confirmed in two frames")
        XCTAssertEqual(g.toastTop, 53, accuracy: 2, "24 CSS below a 29 CSS menu bar")
        XCTAssertEqual(g.toastRightMargin, 16, accuracy: 2, "row 37 right margin")
        XCTAssertEqual(g.toastMaxWidth, reference.width * 0.225, accuracy: 2, "row 37 width is now the cap")

        // Anchored top-right: the right edge and the top do not move with width.
        for width in [g.toastMinWidth, 250, g.toastMaxWidth] as [CGFloat] {
            let rect = g.toastRect(width: width)
            XCTAssertEqual(rect.maxX, reference.width - 16, accuracy: 0.001,
                           "right edge is fixed at width \(width)")
            XCTAssertEqual(rect.minY, 53, accuracy: 0.001, "top edge is fixed at width \(width)")
            XCTAssertEqual(rect.height, g.toastHeight, accuracy: 0.001)
        }

        // The measured pair both land inside the clamp, so neither is distorted.
        for measured in [223.9, 265.4] as [CGFloat] {
            XCTAssertEqual(g.toastRect(width: measured).width, measured, accuracy: 0.001,
                           "the measured width \(measured) passes through unclamped")
        }
        XCTAssertEqual(g.toastRect(width: 900).width, g.toastMaxWidth, accuracy: 0.001, "capped")
        XCTAssertEqual(g.toastRect(width: 10).width, g.toastMinWidth, accuracy: 0.001, "floored")

        XCTAssertEqual(g.toastCornerRadius, reference.width * 0.0164, accuracy: 0.5,
                       "row 70: reuses the prompt bar radius token, no fourth radius")
    }

    func testToastClearsTheEnlargedCardByRow123sMargin() {
        let g = geometry(reference)
        let clearance = g.centreCardRect.minY - (g.toastTop + g.toastHeight)
        XCTAssertGreaterThanOrEqual(clearance, 12, "row 123: toast bottom to card top >= 12 CSS")
        XCTAssertEqual(clearance, 16.6, accuracy: 1.0, "ruling D-8's computed 16.6 CSS")
        XCTAssertEqual(g.centreCardRect.minY, 139.6, accuracy: 1.0, "D-8's card top edge")
    }

    func testToastDoesNotCollideWithTheTopBarPill() {
        // Row 73 states the pill spans x 361.5-982.5 and says the two do not
        // collide. U5 owns the pill; this asserts the toast half. It is checked
        // against the WIDEST the toast can be, because a content-dependent width
        // that only clears at its narrowest clears nothing.
        let g = geometry(reference)
        let pillWidth = reference.width * 0.462
        let pillRect = CGRect(
            x: (reference.width - pillWidth) / 2,
            y: 30,
            width: pillWidth,
            height: reference.width * 0.0298
        )
        XCTAssertFalse(pillRect.intersects(g.toastWidestRect), "row 73: pill and toast do not collide")
        XCTAssertGreaterThan(g.toastWidestRect.minX, pillRect.maxX,
                             "the widest toast still starts right of the pill")
    }

    func testToastClearsTheGridBlockToo() {
        // Row 123 asserts the toast against the carousel card. Grid mode puts a
        // different block in that band, and nothing else checks it.
        let g = geometry(reference)
        let layout = CarouselGridLayout(geometry: g)
        XCTAssertGreaterThan(layout.blockRect.minY, g.toastTop + g.toastHeight,
                             "the grid block clears the toast")
        let promptBarTop = g.viewport.height - g.scaled(34.5) - g.scaled(56.5)
        XCTAssertLessThan(layout.blockRect.maxY, promptBarTop,
                          "the grid block clears the prompt bar")
    }

    // MARK: - Overflow beyond the reference's six sessions

    func testGridBeyondSixCardsStaysInsideTheSafeBand() {
        let g = geometry(reference)
        let layout = CarouselGridLayout(geometry: g, count: 12)
        XCTAssertEqual(layout.rows, 4)
        XCTAssertLessThan(layout.overflowScale, 1, "the block scales down rather than overflowing")
        XCTAssertGreaterThanOrEqual(layout.blockRect.minY, g.overlaySafeBand.lowerBound - 0.5)
        XCTAssertLessThanOrEqual(layout.blockRect.maxY, g.overlaySafeBand.upperBound + 0.5)
        XCTAssertEqual(layout.blockRect.midY, g.centreCardRect.midY, accuracy: tolerance(g),
                       "row 39 survives the overflow case")
        XCTAssertEqual(layout.cardAspect, g.cardAspect, accuracy: 0.01,
                       "row 40 survives the overflow case")
    }
}
