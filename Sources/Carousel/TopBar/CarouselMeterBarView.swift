// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import SwiftUI

/// The one bar primitive both meters use, so row 74's 120 × 4 and row 75's
/// 40 × 4 are the same shape at two widths rather than two implementations.
struct CarouselMeterBarView: View {
    let fraction: Double?
    let width: Double
    let height: Double
    let fill: Color
    let track: Color

    var body: some View {
        Capsule(style: .continuous)
            .fill(track)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(fill)
                    .frame(width: width * min(max(fraction ?? 0, 0), 1), height: height)
            }
            .accessibilityHidden(true)
    }
}
