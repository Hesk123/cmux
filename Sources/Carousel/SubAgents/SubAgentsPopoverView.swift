import SwiftUI

/// The panel the chip opens: every sub-agent of the centred session, parents
/// above their children.
///
/// Takes values rather than the store on purpose. cmux has a standing rule
/// against any view below a lazy-stack boundary holding an observable store
/// reference — violating it reintroduced a 100 % CPU spin (upstream issue
/// #2586) — so the list and its rows are fed plain values and the store stays
/// above the boundary, in the chip.
struct SubAgentsPopoverView: View {
    let rows: [SubAgentOutlineRow]
    let runningCount: Int
    let availability: SubAgentScan.Availability
    let freshness: CarouselDataRoot.Freshness
    let excludedWorkspaceCount: Int
    let presentation: SubAgentsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: presentation.rowSpacing) {
            header
            content
            if case let .stale(_, host) = freshness {
                footnote(SubAgentsStrings.mirrorStale(host: host))
                    .accessibilityIdentifier("carousel.subAgents.stale")
            }
            if excludedWorkspaceCount > 0 {
                footnote(SubAgentsStrings.excludedWorkspaces(excludedWorkspaceCount))
            }
        }
        .padding(presentation.popoverPadding)
        .frame(width: presentation.popoverWidth, alignment: .leading)
        .background(presentation.popoverFill.opacity(0.86), in: panelShape)
        .background(.ultraThinMaterial, in: panelShape)
        .overlay(panelShape.strokeBorder(.white.opacity(0.08), lineWidth: 1))
        .accessibilityIdentifier("carousel.subAgents.popover")
        .accessibilityElement(children: .contain)
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: presentation.popoverCornerRadius, style: .continuous)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(SubAgentsStrings.popoverTitle)
                .font(.system(size: presentation.rowTitleSize, weight: .semibold))
            Spacer(minLength: 0)
            Text(SubAgentsStrings.chipCount(runningCount))
                .font(.system(size: presentation.rowSubtitleSize))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("carousel.subAgents.popover.runningCount")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch availability {
        case .ready where rows.isEmpty:
            footnote(SubAgentsStrings.empty)
                .accessibilityIdentifier("carousel.subAgents.empty")
        case .ready:
            list
        case .outOfScope:
            footnote(SubAgentsStrings.outOfScope)
                .accessibilityIdentifier("carousel.subAgents.outOfScope")
        case let .rootMissing(path):
            footnote(SubAgentsStrings.mirrorMissingAt(path: path))
                .accessibilityIdentifier("carousel.subAgents.degraded")
        case .sessionMissing:
            footnote(SubAgentsStrings.empty)
                .accessibilityIdentifier("carousel.subAgents.empty")
        }
    }

    private var list: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: presentation.rowSpacing) {
                ForEach(rows) { row in
                    SubAgentRowView(row: row, presentation: presentation)
                }
            }
        }
        .frame(maxHeight: presentation.popoverMaxHeight)
        .scrollIndicators(.never)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: presentation.rowSubtitleSize))
            .foregroundStyle(.secondary)
    }
}

#if DEBUG
#Preview("Sub-agents popover") {
    SubAgentsPopoverView(
        rows: SubAgentOutline.rows(for: SubAgentRecord.previewRecords),
        runningCount: 2,
        availability: .ready,
        freshness: .unknown,
        excludedWorkspaceCount: 2,
        presentation: .standard(width: 1344)
    )
    .padding(40)
    .background(.black)
}
#endif
