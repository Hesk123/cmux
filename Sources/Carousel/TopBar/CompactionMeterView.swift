// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import CmuxFoundation
import SwiftUI

/// Row 13 and row 74's third element: a 120 × 4 CSS bar plus a token label.
///
/// The three states are distinct on purpose. `current_usage: null` — the state
/// right after `/compact` and before the first API call — renders "waiting",
/// **not a zero fill**, because an empty bar and a genuinely empty context are
/// the same picture and only one of them is true.
struct CompactionMeterView: View {
    let compaction: CarouselTopBarViewState.CompactionState
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
                width: metrics.compactionBarWidth,
                height: metrics.barHeight,
                fill: isDimmed ? CarouselTopBarPalette.staleMeter : CarouselTopBarPalette.primaryText,
                track: CarouselTopBarPalette.meterTrack
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Context window")
        .accessibilityValue(label)
    }

    private var fraction: Double? {
        switch compaction {
        case .measured(let fraction, _, _): fraction
        case .awaitingFirstResponse, .unavailable: nil
        }
    }

    private var label: String {
        switch compaction {
        case .measured(let fraction, let usedTokens, let windowSize):
            Self.measuredLabel(fraction: fraction, usedTokens: usedTokens, windowSize: windowSize)
        case .awaitingFirstResponse:
            "context — waiting for first response"
        case .unavailable:
            "context unavailable"
        }
    }

    /// Derived label, exposed so a test asserts the string rather than a picture.
    static func measuredLabel(fraction: Double, usedTokens: Int?, windowSize: Int?) -> String {
        let percent = (fraction * 100).rounded()
        let percentText = percent.formatted(.number.precision(.fractionLength(0)))
        guard let usedTokens, let windowSize, windowSize > 0 else {
            return "context \(percentText)%"
        }
        return "context \(percentText)% · \(tokenText(usedTokens)) / \(tokenText(windowSize))"
    }

    static func tokenText(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            let millions = Double(tokens) / 1_000_000
            return "\(millions.formatted(.number.precision(.fractionLength(millions < 10 ? 1 : 0))))M"
        }
        if tokens >= 1_000 {
            return "\((tokens / 1_000).formatted(.number))k"
        }
        return tokens.formatted(.number)
    }
}
