// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// CONTRACT rows 73, 74, 75 and 123, expressed the way the contract's
/// normalization rule requires: **every target is a ratio of window width W,
/// anchored to the reference viewport of 1344 × 1080 logical.** A row that quotes
/// an absolute number quotes it at W = 1344; the ratio is what is asserted, so
/// nothing here voids silently when the window is a different size.
struct CarouselTopBarMetrics: Equatable, Sendable {
    /// The video's logical viewport width, the anchor for every ratio below.
    static let referenceWindowWidth: Double = 1344
    static let referenceWindowHeight: Double = 1080

    let windowWidth: Double

    init(windowWidth: Double) {
        self.windowWidth = max(windowWidth, 1)
    }

    private func scaled(_ referenceValue: Double) -> Double {
        referenceValue * windowWidth / Self.referenceWindowWidth
    }

    // Row 73 — the centred floating pill.
    static let pillWidthRatio: Double = 0.462
    static let pillHeightRatio: Double = 0.0298
    static let cornerRadiusRatio: Double = 0.0164

    var pillWidth: Double { windowWidth * Self.pillWidthRatio }
    var pillHeight: Double { windowWidth * Self.pillHeightRatio }
    var cornerRadius: Double { windowWidth * Self.cornerRadiusRatio }

    /// Row 73 — centred horizontally, so the pill spans these x bounds. Stated as
    /// a value rather than left to the layout because row 73 asserts it does not
    /// collide with the toast, and that is arithmetic, not an assumption.
    var pillMinX: Double { (windowWidth - pillWidth) / 2 }
    var pillMaxX: Double { pillMinX + pillWidth }

    // Row 74 — compaction meter.
    var compactionBarWidth: Double { scaled(120) }
    var barHeight: Double { scaled(4) }

    // Row 75 — usage meters.
    var usageBarWidth: Double { scaled(40) }
    var usageLabelFontSize: Double { scaled(12.5) }

    // Row 70 — the only permitted type size for a chip label is the prompt
    // bar's 13 CSS. No fourth token.
    var chipFontSize: Double { scaled(13) }

    // Internal spacing, derived so it scales with everything else.
    var horizontalInset: Double { scaled(14) }
    var itemSpacing: Double { scaled(10) }
    var separatorHeight: Double { scaled(16) }

    /// Row 123 — the pill's bottom edge must clear the enlarged card's top edge
    /// by at least this, computed at 69.6 CSS in the contract.
    static let minimumPillToCardClearanceRatio: Double = 60 / referenceWindowWidth
    var minimumPillToCardClearance: Double { windowWidth * Self.minimumPillToCardClearanceRatio }
}
