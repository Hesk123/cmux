// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT rows 73, 74, 75, 123 — asserted as ratios of window width, at three
/// window sizes, because the contract's normalization rule makes the ratio the
/// thing that is asserted and the absolute number only its value at W = 1344.
@Suite("Carousel top bar metrics")
struct CarouselTopBarMetricsTests {
    private let widths: [Double] = [1344, 1128, 1920]

    @Test("Row 73: pill geometry is the stated ratio of W at every window size")
    func pillGeometryIsRatioOfWindowWidth() {
        for width in widths {
            let metrics = CarouselTopBarMetrics(windowWidth: width)
            #expect(abs(metrics.pillWidth / width - 0.462) < 0.0001)
            #expect(abs(metrics.pillHeight / width - 0.0298) < 0.0001)
            #expect(abs(metrics.cornerRadius / width - 0.0164) < 0.0001)
        }
    }

    @Test("Row 73: at the reference W = 1344 the pill measures 621 x 40, radius 22")
    func pillMatchesReferenceValues() {
        let metrics = CarouselTopBarMetrics(windowWidth: 1344)
        #expect(abs(metrics.pillWidth - 620.9) < 2.0)
        #expect(abs(metrics.pillHeight - 40.0) < 2.0)
        #expect(abs(metrics.cornerRadius - 22.0) < 2.0)
    }

    @Test("Row 73: the centred pill does not reach the toast slot")
    func pillDoesNotCollideWithToast() {
        // The toast spans x 1026-1328 at W = 1344 (row 37). The contract settles
        // this by arithmetic rather than assumption, so the test does too.
        let metrics = CarouselTopBarMetrics(windowWidth: 1344)
        #expect(abs(metrics.pillMinX - 361.5) < 2.0)
        #expect(abs(metrics.pillMaxX - 982.5) < 2.0)
        #expect(metrics.pillMaxX < 1026)
    }

    @Test("Row 74: the compaction bar is 120 x 4 CSS at the reference width")
    func compactionBarGeometry() {
        let metrics = CarouselTopBarMetrics(windowWidth: 1344)
        #expect(abs(metrics.compactionBarWidth - 120) < 0.5)
        #expect(abs(metrics.barHeight - 4) < 0.5)
    }

    @Test("Row 75: each usage bar is 40 x 4 CSS with a 12.5 CSS label")
    func usageBarGeometry() {
        let metrics = CarouselTopBarMetrics(windowWidth: 1344)
        #expect(abs(metrics.usageBarWidth - 40) < 0.5)
        #expect(abs(metrics.barHeight - 4) < 0.5)
        #expect(abs(metrics.usageLabelFontSize - 12.5) < 0.5)
    }

    @Test("Row 70: the chip label uses the prompt bar's 13 CSS type size, not a fourth token")
    func chipTypeSizeMatchesPromptBar() {
        #expect(abs(CarouselTopBarMetrics(windowWidth: 1344).chipFontSize - 13) < 0.5)
    }

    @Test("Row 123: the pill-to-card clearance floor scales with W and is 60 CSS at reference")
    func clearanceFloorScales() {
        #expect(abs(CarouselTopBarMetrics(windowWidth: 1344).minimumPillToCardClearance - 60) < 0.5)
        let wide = CarouselTopBarMetrics(windowWidth: 1920)
        #expect(abs(wide.minimumPillToCardClearance / 1920 - 60.0 / 1344) < 0.0001)
    }

    @Test("A zero or negative window width cannot produce a negative or NaN layout")
    func degenerateWidthIsClamped() {
        for width in [0.0, -500.0] {
            let metrics = CarouselTopBarMetrics(windowWidth: width)
            #expect(metrics.pillWidth > 0)
            #expect(metrics.pillWidth.isFinite)
            #expect(metrics.cornerRadius >= 0)
        }
    }
}

/// Row 75's thresholds. H1 asserts a colour at the 50 %, 80 % and 95 % fixtures,
/// so each of those points must fall in a distinct band from its neighbour.
struct CarouselUsageSeverityTests {
    @Test("Row 75: 50, 80 and 95 each begin a distinct band")
    func thresholdsAreDistinct() {
        typealias Usage = CarouselTopBarViewState.UsageState
        #expect(Usage.severity(forPercent: 0) == .healthy)
        #expect(Usage.severity(forPercent: 49.9) == .healthy)
        #expect(Usage.severity(forPercent: 50) == .elevated)
        #expect(Usage.severity(forPercent: 79.9) == .elevated)
        #expect(Usage.severity(forPercent: 80) == .high)
        #expect(Usage.severity(forPercent: 94.9) == .high)
        #expect(Usage.severity(forPercent: 95) == .critical)
        #expect(Usage.severity(forPercent: 100) == .critical)
    }
}
