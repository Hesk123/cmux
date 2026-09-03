import SwiftUI

/// CONTRACT row 73 — the centred floating pill carrying rows 12, 13, 15, 74, 75,
/// 120, 125, 126 and 127.
///
/// **This is the single presentation view the pending design direction skins.**
/// Dawid has five previews in front of him and has not chosen one. Everything
/// underneath — the bridge, the tee, the parsers, the join, the liveness rules —
/// is complete and tested against `CarouselTopBarViewState`, so the pick changes
/// this file, `CarouselTopBarPalette` and nothing else. No liveness rule and no
/// test moves with the skin.
///
/// The bar deliberately does not animate its numbers. Emil's frequency test puts
/// a value that changes on most assistant turns in the "remove or drastically
/// reduce" band, and a rolling odometer on a usage percentage would draw the eye
/// to the one element in the window that should never compete with the terminal.
struct CarouselTopBarView: View {
    let state: CarouselTopBarViewState
    let metrics: CarouselTopBarMetrics

    var body: some View {
        HStack(spacing: metrics.itemSpacing) {
            CarouselTopBarActivityView(activity: state.agentActivity, metrics: metrics)
            CarouselModelChipView(
                model: state.model,
                metrics: metrics,
                isDimmed: state.suppressesLiveNumbers
            )
            .accessibilityIdentifier(CarouselTopBarAccessibility.modelChip)

            Rectangle()
                .fill(CarouselTopBarPalette.separator)
                .frame(width: 1, height: metrics.separatorHeight)
                .accessibilityHidden(true)

            if state.suppressesLiveNumbers {
                CarouselTopBarStatusView(state: state, metrics: metrics)
                    .accessibilityIdentifier(CarouselTopBarAccessibility.statusMessage)
                Spacer(minLength: 0)
            } else {
                CompactionMeterView(
                    compaction: state.compaction,
                    metrics: metrics,
                    isDimmed: false
                )
                .accessibilityIdentifier(CarouselTopBarAccessibility.compactionLabel)

                Spacer(minLength: metrics.itemSpacing)

                UsageMetersView(
                    fiveHour: state.fiveHour,
                    sevenDay: state.sevenDay,
                    metrics: metrics,
                    isDimmed: false
                )
            }
        }
        .padding(.horizontal, metrics.horizontalInset)
        .frame(width: metrics.pillWidth, height: metrics.pillHeight)
        .background(CarouselTopBarPalette.surface, in: .rect(cornerRadius: metrics.cornerRadius, style: .continuous))
        .accessibilityIdentifier(CarouselTopBarAccessibility.pill)
    }
}

#Preview("Live") {
    CarouselTopBarView(
        state: CarouselTopBarViewState(
            model: .named("Fable 5.1"),
            compaction: .measured(fraction: 0.634, usedTokens: 126_800, windowSize: 200_000),
            fiveHour: .measured(percent: 62, resetsAt: Date().addingTimeInterval(3600)),
            sevenDay: .measured(percent: 41, resetsAt: Date().addingTimeInterval(86_400)),
            liveness: .live,
            agentActivity: .running
        ),
        metrics: CarouselTopBarMetrics(windowWidth: 1344)
    )
    .padding(40)
    .background(.black)
}

#Preview("Stale") {
    CarouselTopBarView(
        state: CarouselTopBarViewState(
            model: .named("Fable 5.1"),
            liveness: .stale(age: 312, capturedAt: Date().addingTimeInterval(-312)),
            agentActivity: .unknown
        ),
        metrics: CarouselTopBarMetrics(windowWidth: 1344)
    )
    .padding(40)
    .background(.black)
}
