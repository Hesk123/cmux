// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
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
        // NOTE: no .accessibilityIdentifier(popover) on this container. An
        // explicit identifier swallows its whole subtree's identifiers
        // (outermost wins), which would make every row id unresolvable. The
        // open-popover signal is the header's runningCount id below, which has
        // no identifier-bearing ancestors and resolves; `.contain` still
        // exposes each row as its own element.
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
        // Eager VStack, not LazyVStack: in an overlay the scroll proposes an
        // unbounded axis, against which a lazy stack measures ~zero and the
        // panel collapses to its header (rows present in data, absent on
        // screen and in accessibility). The popover caps height at
        // popoverMaxHeight and scrolls past it; materialising at most a few
        // hundred small rows eagerly is what makes the content exist to scroll.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: presentation.rowSpacing) {
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
