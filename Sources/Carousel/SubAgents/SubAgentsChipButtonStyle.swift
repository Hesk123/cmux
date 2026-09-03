// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import SwiftUI

/// Press feedback for the sub-agents chip.
///
/// The scale lands on pointer-down rather than on release, which is what makes
/// a control feel like it heard you. Kept subtle, and dropped entirely under
/// reduced motion, where the opacity change carries the same information
/// without the movement.
struct SubAgentsChipButtonStyle: ButtonStyle {
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.97)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
