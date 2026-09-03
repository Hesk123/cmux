// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import SwiftUI

/// The carousel's prompt bar — CONTRACT rows 32, 33, 34, 6 and 61.
///
/// Screen-anchored rather than attached to the card (row 33): the caller places
/// it with `metrics.bottomInset` from the container's bottom edge, so its
/// distance to that edge is constant while the card's height changes.
struct CarouselPromptBarView: View {
    let sessionName: String?
    let windowWidth: Double
    @Binding var composedLine: String
    let onSubmit: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFieldFocused: Bool

    private var metrics: CarouselPromptBarMetrics {
        CarouselPromptBarMetrics(windowWidth: windowWidth)
    }

    private var buttonMode: CarouselComposeButtonMode {
        CarouselComposeButtonMode(isComposedLineEmpty: composedLine.isEmpty)
    }

    var body: some View {
        HStack(spacing: metrics.actionButtonTrailingInset) {
            if let sessionName {
                CarouselPromptSessionChipView(
                    sessionName: sessionName,
                    windowWidth: windowWidth
                )
            }

            TextField(
                String(
                    localized: "carousel.promptBar.placeholder",
                    defaultValue: "Ask me anything"
                ),
                text: $composedLine
            )
            .textFieldStyle(.plain)
            .font(.system(size: metrics.height * 0.28))
            .focused($isFieldFocused)
            .onSubmit(submit)
            .accessibilityIdentifier(CarouselPromptBarAccessibility.textField)

            CarouselComposeActionButton(
                mode: buttonMode,
                diameter: metrics.actionButtonDiameter,
                reduceMotion: reduceMotion,
                action: submit
            )
        }
        .padding(.horizontal, metrics.actionButtonTrailingInset)
        .frame(width: metrics.width, height: metrics.height)
        .background(
            CarouselPromptBarPalette.barFill,
            // Circular: Twin Rails frames the deck with two identical rails,
            // and row 32's radius band (20.75-22.00 CSS) was fitted circularly.
            in: .rect(cornerRadius: metrics.cornerRadius, style: .circular)
        )
        .accessibilityIdentifier(CarouselPromptBarAccessibility.bar)
        // Ruling D-1: the prompt bar owns keyboard focus by default in
        // carousel mode, so it claims first responder as soon as it appears.
        .onAppear { isFieldFocused = true }
    }

    /// Row 65 (input half): the composed line goes to the centred pty, then the
    /// field clears. Clearing is the caller's to schedule one frame later via
    /// `CarouselSendSequence.inputClearDelay`; clearing here synchronously would
    /// beat the terminal echo the row measures against.
    private func submit() {
        let line = composedLine
        guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmit(line)
    }
}
