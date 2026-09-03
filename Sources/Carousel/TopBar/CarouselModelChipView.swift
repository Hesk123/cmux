import CmuxFoundation
import SwiftUI

/// Row 12 and row 74's first element: the model name on a `#262E37` pill.
struct CarouselModelChipView: View {
    let model: CarouselTopBarViewState.ModelState
    let metrics: CarouselTopBarMetrics
    let isDimmed: Bool

    var body: some View {
        Text(label)
            .cmuxFont(size: metrics.chipFontSize, weight: .medium)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(isDimmed ? CarouselTopBarPalette.staleText : CarouselTopBarPalette.primaryText)
            .padding(.horizontal, metrics.itemSpacing)
            .padding(.vertical, metrics.itemSpacing / 3)
            .background(CarouselTopBarPalette.chip, in: .capsule)
            .accessibilityLabel(accessibilityLabel)
    }

    private var label: String {
        switch model {
        case .named(let name): name
        case .unavailable: "No model"
        }
    }

    private var accessibilityLabel: String {
        switch model {
        case .named(let name): "Model \(name)"
        case .unavailable: "Model unavailable"
        }
    }
}
