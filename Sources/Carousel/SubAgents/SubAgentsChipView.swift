// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import SwiftUI

/// The `⚙ N agents` control that sits in the card header, left of the status
/// pill, and opens the sub-agents popover.
///
/// Placement inside the header is the card's business, not this view's: it
/// draws a pill and hosts its own popover, so the eventual chrome direction can
/// move it without touching anything here.
struct SubAgentsChipView: View {
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    let store: SubAgentsStore
    let presentation: SubAgentsPresentation
    /// Overrides the environment for tests, which cannot set an accessibility
    /// preference on the machine running them.
    var reduceMotionOverride: Bool?

    @State private var isPopoverPresented = false

    private var reduceMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        Button(action: togglePopover) {
            chipLabel
        }
        .buttonStyle(SubAgentsChipButtonStyle(reduceMotion: reduceMotion))
        .disabled(!store.isInteractive)
        .accessibilityIdentifier("carousel.subAgents.chip")
        .accessibilityLabel(SubAgentsStrings.chipAccessibilityLabel)
        .accessibilityValue(chipText)
        .help(helpText)
        // The panel's top edge meets the chip's bottom edge: redefining the
        // overlay's `.bottom` guide as its own `.top` turns a bottom-aligned
        // overlay into one that hangs below the control (CONTRACT row 72's
        // 8 px anchor tolerance).
        .overlay(alignment: .bottomLeading) {
            popoverLayer
                .alignmentGuide(.bottom) { $0[.top] }
                .offset(y: presentation.popoverAnchorGap)
        }
    }

    private var chipLabel: some View {
        HStack(spacing: presentation.chipSpacing) {
            Image(systemName: "gearshape")
                .font(.system(size: presentation.chipIconSize, weight: .medium))
            Text(chipText)
                .font(.system(size: presentation.chipLabelSize, weight: .medium))
                .accessibilityIdentifier("carousel.subAgents.chip.label")
            if store.excludedWorkspaceCount > 0 {
                excludedBadge
            }
        }
        .foregroundStyle(isDegraded ? .secondary : .primary)
        .padding(.horizontal, presentation.chipHorizontalPadding)
        .padding(.vertical, presentation.chipVerticalPadding)
        .background(presentation.chipFill.opacity(0.9), in: .capsule)
        .background(.ultraThinMaterial, in: .capsule)
    }

    /// CONTRACT row 132: workspaces excluded from the card list because they
    /// are not mounted are counted here, so nothing disappears silently.
    private var excludedBadge: some View {
        Text(verbatim: "+\(store.excludedWorkspaceCount)")
            .font(.system(size: presentation.chipLabelSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("carousel.subAgents.excludedBadge")
            .accessibilityLabel(SubAgentsStrings.excludedWorkspaces(store.excludedWorkspaceCount))
    }

    @ViewBuilder
    private var popoverLayer: some View {
        if isPopoverPresented {
            SubAgentsPopoverView(
                rows: store.rows,
                runningCount: store.scan.runningCount,
                availability: store.scan.availability,
                freshness: store.scan.freshness,
                excludedWorkspaceCount: store.excludedWorkspaceCount,
                presentation: presentation
            )
            .transition(popoverTransition)
            .zIndex(1)
        }
    }

    /// Scale-in from the chip, not a fade. The reference video has no
    /// origin-aware transition anywhere, which is why introducing one here
    /// reads as an upgrade rather than an inconsistency.
    private var popoverTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .scale(
            scale: SubAgentsPresentation.openInitialScale,
            anchor: .topLeading
        ).combined(with: .opacity)
    }

    private var chipText: String {
        switch store.scan.availability {
        case .ready:
            SubAgentsStrings.chipCount(store.scan.runningCount)
        case .outOfScope:
            SubAgentsStrings.outOfScope
        case .rootMissing:
            SubAgentsStrings.mirrorMissing
        case .sessionMissing:
            SubAgentsStrings.empty
        }
    }

    private var isDegraded: Bool {
        switch store.scan.availability {
        case .ready: !isMirrorFresh
        case .outOfScope, .rootMissing, .sessionMissing: true
        }
    }

    /// A mirror that has stopped pulling leaves data that parses perfectly and
    /// is simply old. `unknown` means it has never run against this root, which
    /// is a different problem and is not staleness.
    private var isMirrorFresh: Bool {
        if case .stale = store.scan.freshness { return false }
        return true
    }

    private var helpText: String {
        if case let .stale(_, host) = store.scan.freshness {
            return SubAgentsStrings.mirrorStale(host: host)
        }
        if store.excludedWorkspaceCount > 0 {
            return SubAgentsStrings.excludedWorkspaces(store.excludedWorkspaceCount)
        }
        return SubAgentsStrings.chipAccessibilityLabel
    }

    private func togglePopover() {
        withAnimation(SubAgentsPresentation.openAnimation(reduceMotion: reduceMotion)) {
            isPopoverPresented.toggle()
        }
    }
}

#if DEBUG
#Preview("Sub-agents chip") {
    SubAgentsChipView(store: .preview, presentation: .standard(width: 1344))
        .padding(60)
        .background(.black)
}
#endif
