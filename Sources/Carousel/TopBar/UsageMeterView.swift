import CmuxFoundation
import SwiftUI

/// One of row 75's two meters: `5h N %` or `wk N %`, a 12.5 CSS label plus a
/// 40 × 4 CSS bar, with the reset time as a relative time.
///
/// Row 120's whole point lives in the `.unavailable` branch: when `rate_limits`
/// is absent there is no percentage to show, and this renders that fact. There
/// is no code path in this view that can produce a number the payload did not
/// contain.
struct UsageMeterView: View {
    let title: String
    let usage: CarouselTopBarViewState.UsageState
    let metrics: CarouselTopBarMetrics
    let isDimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.itemSpacing / 3) {
            Text(label)
                .cmuxFont(size: metrics.usageLabelFontSize, weight: .medium)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(isDimmed ? CarouselTopBarPalette.staleText : CarouselTopBarPalette.secondaryText)
            CarouselMeterBarView(
                fraction: fraction,
                width: metrics.usageBarWidth,
                height: metrics.barHeight,
                fill: fillColor,
                track: CarouselTopBarPalette.meterTrack
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityValue)
    }

    private var fraction: Double? {
        switch usage {
        case .measured(let percent, _): percent / 100
        case .unavailable: nil
        }
    }

    private var fillColor: Color {
        guard !isDimmed, let severity = usage.severity else { return CarouselTopBarPalette.staleMeter }
        return CarouselTopBarPalette.meterFill(for: severity)
    }

    private var label: String {
        switch usage {
        case .measured(let percent, _):
            "\(title) \(percent.formatted(.number.precision(.fractionLength(0))) )%"
        case .unavailable:
            "\(title) —"
        }
    }

    private var accessibilityTitle: String {
        title == "5h" ? "Five hour usage" : "Seven day usage"
    }

    private var accessibilityValue: String {
        switch usage {
        case .measured(let percent, let resetsAt):
            if let resetsAt {
                "\(percent.formatted(.number.precision(.fractionLength(0)))) percent used, resets \(resetsAt.formatted(.relative(presentation: .numeric)))"
            } else {
                "\(percent.formatted(.number.precision(.fractionLength(0)))) percent used"
            }
        case .unavailable:
            "Unavailable"
        }
    }
}
