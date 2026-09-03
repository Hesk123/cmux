// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT rows 32, 33, 34 and 35, measured at the reference window width and
/// then at two others to prove the ratios hold rather than the constants.
@MainActor
@Suite("Carousel prompt bar geometry")
struct CarouselPromptBarGeometryTests {
    /// H1's default geometry tolerance.
    private static let toleranceCSS: Double = 2

    private static func isClose(
        _ lhs: Double,
        _ rhs: Double,
        within tolerance: Double = toleranceCSS
    ) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    // MARK: - Row 32

    @Test("At W = 1344 the bar reproduces the video's measured size and radius")
    func barMatchesTheReferenceFrame() {
        let metrics = CarouselPromptBarMetrics(windowWidth: 1344)

        // VIDEO-REVIEW §1.4: 1242 x 113 device = 621 x 56.5 CSS, radius 22 CSS.
        #expect(Self.isClose(metrics.width, 621))
        #expect(Self.isClose(metrics.height, 56.5))
        #expect(Self.isClose(metrics.cornerRadius, 22))
    }

    @Test("The bar is a rounded rect, not a stadium")
    func barIsNotAStadium() {
        // VIDEO-REVIEW §1.4 reads a 25-device-pixel straight run along the edge,
        // which a stadium would not have.
        #expect(!CarouselPromptBarMetrics(windowWidth: 1344).isStadium)
    }

    @Test("Every dimension scales with window width")
    func geometryIsRatioBased() {
        let reference = CarouselPromptBarMetrics(windowWidth: 1344)
        let wide = CarouselPromptBarMetrics(windowWidth: 2688)

        #expect(Self.isClose(wide.width, reference.width * 2))
        #expect(Self.isClose(wide.height, reference.height * 2))
        #expect(Self.isClose(wide.cornerRadius, reference.cornerRadius * 2))
        #expect(Self.isClose(wide.actionButtonDiameter, reference.actionButtonDiameter * 2))
    }

    // MARK: - Row 33 — screen-anchored, not card-anchored

    @Test("Distance to the container bottom is constant across window heights")
    func barIsScreenAnchored() {
        let metrics = CarouselPromptBarMetrics(windowWidth: 1344)
        let heights: [Double] = [900, 1080, 1400]

        let distances = heights.map { metrics.distanceToContainerBottom(inContainerOfHeight: $0) }

        #expect(Self.isClose(distances[0], 34.5))
        for distance in distances {
            #expect(
                Self.isClose(distance, distances[0]),
                "the bar drifted from the bottom edge when the container height changed"
            )
        }
    }

    @Test("The bar's top-space origin is computed from the container height")
    func barTopOriginMovesWithTheContainer() {
        // The other half of row 33: `distanceToContainerBottom` pins the gap,
        // this pins that placement is computed from the container at all. A
        // constant origin would pass the gap test while welded in place.
        let metrics = CarouselPromptBarMetrics(windowWidth: 1344)
        for height in [900.0, 1080.0, 1400.0] {
            #expect(
                Self.isClose(
                    metrics.originYFromTop(inContainerOfHeight: height),
                    height - 34.5 - metrics.height))
        }
        #expect(
            metrics.originYFromTop(inContainerOfHeight: 1400)
                > metrics.originYFromTop(inContainerOfHeight: 900))
    }

    @Test("The bar is narrower than the card it sits under")
    func barIsNarrowerThanTheCard() {
        // CONTRACT row 9: the card is 72 % of W. The bar is 46.2 %.
        let metrics = CarouselPromptBarMetrics(windowWidth: 1344)
        let cardWidth = 0.72 * 1344
        #expect(metrics.width < cardWidth)
    }

    // MARK: - Row 34

    @Test("The action button is a circle, right-inset and vertically centred")
    func actionButtonMatchesRow34() {
        let metrics = CarouselPromptBarMetrics(windowWidth: 1344)

        // VIDEO-REVIEW §1.4: 70 x 70 device = 35 x 35 CSS, right inset 10.5 CSS.
        #expect(Self.isClose(metrics.actionButtonDiameter, 35))
        #expect(Self.isClose(metrics.actionButtonTrailingInset, 10.5))
        #expect(Self.isClose(metrics.actionButtonCentreY, metrics.height / 2))

        let trailingGap = metrics.width - (metrics.actionButtonOriginX + metrics.actionButtonDiameter)
        #expect(Self.isClose(trailingGap, metrics.actionButtonTrailingInset))
        #expect(metrics.actionButtonDiameter < metrics.height, "the button must fit inside the bar")
    }

    // MARK: - Row 35

    @Test("The session chip hugs its label, so two labels give two widths")
    func chipWidthFitsTheLabel() {
        let metrics = CarouselSessionChipMetrics(windowWidth: 1344)

        let shortWidth = metrics.chipWidth(for: "Slack")
        let longWidth = metrics.chipWidth(for: "Calendar")

        #expect(
            longWidth > shortWidth,
            "a fixed-width chip would pass every other row and fail only here"
        )

        // Row 35's hug property, stated without restating the definition:
        // the chrome cancels out of a width difference, so the gap between two
        // chips equals the gap between their labels. A pinned or clamped width
        // fails here while passing the ordering check above.
        let pairs = [("Slack", "Calendar"), ("Notion", "Lovable"), ("Figma", "Calendar")]
        for (short, long) in pairs {
            let chipGap = metrics.chipWidth(for: long) - metrics.chipWidth(for: short)
            let labelGap = metrics.labelWidth(for: long) - metrics.labelWidth(for: short)
            #expect(
                Self.isClose(chipGap, labelGap, within: 1),
                "chrome must cancel out of a width difference")
        }
    }

    @Test("Chip label point size is the video's ~13 CSS, and scales with W")
    func chipLabelPointSize() {
        #expect(Self.isClose(CarouselSessionChipMetrics(windowWidth: 1344).labelPointSize, 13))
        #expect(Self.isClose(CarouselSessionChipMetrics(windowWidth: 2688).labelPointSize, 26))
    }

    @Test("The chip fits inside the bar")
    func chipFitsTheBar() {
        let bar = CarouselPromptBarMetrics(windowWidth: 1344)
        let chip = CarouselSessionChipMetrics(windowWidth: 1344)
        #expect(chip.height < bar.height)
        #expect(chip.chipWidth(for: "Calendar") < bar.width)
    }

    // MARK: - Colours

    @Test("Sampled fills match the video")
    func paletteMatchesTheSampledColours() {
        // Row 32 and row 35, VIDEO-REVIEW §1.4.
        #expect(CarouselPromptBarPalette.barFillComponents == (11, 21, 29))
        #expect(CarouselPromptBarPalette.sessionChipFillComponents == (38, 46, 55))
        #expect(CarouselPromptBarPalette.barFillOpacity < 1, "row 32 says translucent")
        #expect(
            CarouselPromptBarPalette.actionButtonFillComponents == (10, 132, 255),
            "row 34 is system blue #0A84FF, never the user's accent colour")
    }
}
