// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import SwiftUI

/// Row 75 — both usage meters at the right end of the pill, with their reset
/// times. The reset time is rendered as a relative time by `Text`'s own format
/// style rather than a stored formatter.
struct UsageMetersView: View {
    let fiveHour: CarouselTopBarViewState.UsageState
    let sevenDay: CarouselTopBarViewState.UsageState
    let metrics: CarouselTopBarMetrics
    let isDimmed: Bool

    var body: some View {
        HStack(spacing: metrics.itemSpacing) {
            UsageMeterView(title: "5h", usage: fiveHour, metrics: metrics, isDimmed: isDimmed)
            UsageMeterView(title: "wk", usage: sevenDay, metrics: metrics, isDimmed: isDimmed)
        }
    }
}
