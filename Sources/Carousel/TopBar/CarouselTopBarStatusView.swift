// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import CmuxFoundation
import SwiftUI

/// Renders whatever the bar is currently unable to claim: row 76's stale state,
/// row 117's degraded source, row 126's dead session, and the no-session and
/// no-snapshot cases. Rows 13, 15 and 120 all require a defined state here
/// instead of a number, so the state has one place to be rendered.
struct CarouselTopBarStatusView: View {
    let state: CarouselTopBarViewState
    let metrics: CarouselTopBarMetrics

    var body: some View {
        Text(message)
            .cmuxFont(size: metrics.usageLabelFontSize, weight: .medium)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(CarouselTopBarPalette.staleText)
            .accessibilityLabel(message)
    }

    private var message: String { Self.message(for: state) }

    /// Exposed so a test asserts the sentence, not a screenshot.
    static func message(for state: CarouselTopBarViewState) -> String {
        if let degraded = state.degradedSourceDescription { return degraded }
        switch state.liveness {
        case .live:
            return ""
        case .stale(let age, let capturedAt):
            let seconds = Int(age.rounded())
            return "stale — captured \(capturedAt.formatted(date: .omitted, time: .standard)), \(seconds)s ago"
        case .noSnapshot:
            return "no statusline snapshot for this session yet"
        case .deadSession:
            return "session ended"
        case .noSession:
            return "no Claude Code session on this card"
        }
    }
}
