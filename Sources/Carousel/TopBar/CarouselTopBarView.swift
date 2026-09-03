// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
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

    /// U4 sub-agents chip, mounted at the pill's trailing end (Twin Rails pick).
    /// Held in `@State` so the store (and its watcher) survives re-renders;
    /// constructing it inline in `body` would tear down and rebuild the watch
    /// on every state change. This view is a plain `HStack` pill — it sits
    /// below no `LazyVStack`/`List`/`ForEach` boundary, so holding the
    /// observable store here respects the list-boundary rule.
    @State private var subAgentsStore = CarouselTopBarView.makeSubAgentsStore()

    var body: some View {
        // Shared with the rail-level excluded-workspace badge below so the
        // two stay in the same type scale.
        let chipPresentation = SubAgentsPresentation.standard(width: CGFloat(metrics.windowWidth))
        return HStack(spacing: metrics.itemSpacing) {
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

            SubAgentsChipView(
                store: subAgentsStore,
                presentation: chipPresentation
            )

            // CONTRACT row 132: the unmounted-workspace count, visible on the
            // rail next to the chip. It lives here rather than inside the chip
            // button because an explicit accessibilityIdentifier swallows its
            // whole subtree's identifiers (outermost wins): nested in the
            // button, this badge could never resolve its own id while the
            // button carries the chip's. As the button's sibling it does.
            if subAgentsStore.excludedWorkspaceCount > 0 {
                Text(verbatim: "+\(subAgentsStore.excludedWorkspaceCount)")
                    .font(.system(size: chipPresentation.chipLabelSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("carousel.subAgents.excludedBadge")
                    .accessibilityLabel(SubAgentsStrings.excludedWorkspaces(subAgentsStore.excludedWorkspaceCount))
            }
        }
        .padding(.horizontal, metrics.horizontalInset)
        .frame(width: metrics.pillWidth, height: metrics.pillHeight)
        // Circular, matching the prompt bar: Twin Rails frames the deck with
        // two identical rails, and row 32's radius band was fitted circularly.
        .background(CarouselTopBarPalette.surface, in: .rect(cornerRadius: metrics.cornerRadius, style: .circular))
        // NOTE: no .accessibilityIdentifier(pill) here. A container identifier
        // shadows every child's identifier in this toolchain's a11y tree (the
        // chip's own id reads back as the pill's), which un-skips nothing and
        // breaks the row-11 contract. The constant stays in
        // CarouselTopBarAccessibility for future use.
        .onAppear { subAgentsStore.start() }
        .onDisappear { subAgentsStore.stop() }
    }

    /// Builds the chip's store. Root comes from `CarouselDataRoot.resolve()`,
    /// whose first step reads `CMUX_CAROUSEL_DATA_ROOT`, so UI tests pointing
    /// the app at a fixture root are picked up with no extra plumbing.
    /// Session comes from the UI-test launch env only; production session
    /// routing (the centred card) is owned by the routing adapter, which will
    /// call `update(root:session:)` — there is deliberately no production
    /// session source here, and a nil key renders the existing U4
    /// out-of-scope state.
    private static func makeSubAgentsStore() -> SubAgentsStore {
        let environment = ProcessInfo.processInfo.environment
        let root = CarouselDataRoot.resolve()
        let session: SubAgentsSessionKey? = {
            guard let slug = environment["CMUX_UI_TEST_CAROUSEL_SESSION_SLUG"],
                  let id = environment["CMUX_UI_TEST_CAROUSEL_SESSION_ID"] else { return nil }
            return SubAgentsSessionKey(projectSlug: slug, sessionID: id)
        }()
        // TODO(card-list): feed the real unmounted-workspace count from the
        // card list here; until then only the UI-test launch env sets it.
        let excludedWorkspaceCount: Int = {
            guard let raw = environment["CMUX_UI_TEST_CAROUSEL_UNMOUNTED_WORKSPACES"],
                  let value = Int(raw) else { return 0 }
            return value
        }()
        return SubAgentsStore(
            root: root,
            session: session,
            excludedWorkspaceCount: excludedWorkspaceCount
        )
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
