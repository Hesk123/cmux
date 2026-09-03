// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import AppKit
import SwiftUI

/// Row 70 — every addition reuses one of the three surfaces the reference
/// defines. These are those surfaces and nothing else; a fourth fill token is a
/// contract failure, so new colours are added here, visibly, or not at all.
///
/// This is also the seam the not-yet-chosen design direction skins: the five
/// design previews differ in palette and material, not in what the bar says, so
/// the pick lands here and in `CarouselTopBarStyle` rather than in the views.
enum CarouselTopBarPalette {
    /// Row 73 — the top bar pill and the prompt bar share this fill.
    static let surface = Color(nsColor: NSColor(hex: "#0B151D") ?? .black)
    /// Row 74 — the model chip, same token as the prompt bar's session chip.
    static let chip = Color(nsColor: NSColor(hex: "#262E37") ?? .darkGray)

    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.55)
    static let separator = Color.white.opacity(0.12)
    static let meterTrack = Color.white.opacity(0.14)

    /// Row 75's thresholds.
    static func meterFill(for severity: CarouselTopBarViewState.UsageState.Severity) -> Color {
        switch severity {
        case .healthy: Color(nsColor: NSColor(hex: "#4ADE80") ?? .systemGreen)
        case .elevated: Color(nsColor: NSColor(hex: "#FBBF24") ?? .systemYellow)
        case .high: Color(nsColor: NSColor(hex: "#F87171") ?? .systemRed)
        case .critical: Color(nsColor: NSColor(hex: "#DC2626") ?? .systemRed)
        }
    }

    /// Row 76 — the stale rendering. Greyed, so no measured value reads as current.
    static let staleText = Color.white.opacity(0.38)
    static let staleMeter = Color.white.opacity(0.18)
}
