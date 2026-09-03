// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import SwiftUI

/// Row 127's signal, rendered. `.unknown` is a distinct appearance from `.idle`,
/// which is the whole reason the row requires a max age: an agent whose state
/// cannot be determined must not be drawn as an agent that is doing nothing.
struct CarouselTopBarActivityView: View {
    let activity: CarouselAgentActivity
    let metrics: CarouselTopBarMetrics

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: metrics.barHeight * 1.6, height: metrics.barHeight * 1.6)
            .overlay {
                Circle()
                    .strokeBorder(CarouselTopBarPalette.separator, lineWidth: activity == .unknown ? 1 : 0)
            }
            .accessibilityLabel("Agent status")
            .accessibilityValue(label)
            .accessibilityIdentifier(CarouselTopBarAccessibility.activityIndicator)
    }

    private var fill: Color {
        switch activity {
        case .running: CarouselTopBarPalette.meterFill(for: .healthy)
        case .idle: CarouselTopBarPalette.secondaryText
        case .unknown: .clear
        }
    }

    private var label: String {
        switch activity {
        case .running: "running"
        case .idle: "idle"
        case .unknown: "unknown"
        }
    }
}
