// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// Accessibility identifiers the H3 (XCUITest) rows address. cmux already uses
/// `accessibilityIdentifier` in 41 source files, so element geometry and text are
/// assertable via `XCUIElement.frame` and `.label` — these are the handles rows
/// 12, 13, 15, 73, 75, 120, 125, 126 and 127 use.
enum CarouselTopBarAccessibility {
    static let pill = "carousel.topbar.pill"
    static let modelChip = "carousel.topbar.model"
    static let compactionLabel = "carousel.topbar.compaction"
    static let fiveHourLabel = "carousel.topbar.usage.fiveHour"
    static let sevenDayLabel = "carousel.topbar.usage.sevenDay"
    static let statusMessage = "carousel.topbar.status"
    static let activityIndicator = "carousel.topbar.activity"
}
