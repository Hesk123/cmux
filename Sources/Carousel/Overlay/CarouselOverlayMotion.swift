// Added 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 67, 68, 77, 78, 113.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore

/// The single place a duration or a timing curve exists for the U6 overlay —
/// the grid transition, the selection ring and the toast.
///
/// U2 owns `CarouselMotion.swift` and the same rule for the carousel's own
/// motion. This file does not duplicate any of U2's constants; it holds only
/// the four U6 durations, and its reduce-motion provider is re-pointed at
/// `CarouselMotion.reduceMotion` in one line at integration (MAKER-U6.md,
/// section Integration) so the build ends with one provider, not two.
///
/// Duration choices, against the Emil Kowalski decision framework and Apple's
/// Designing Fluid Interfaces:
///
/// * `gridTransition` **280 ms**. CONTRACT row 77 needs at least 12 frames of
///   continuous interpolation, which is 200 ms at 60 Hz; Emil caps UI motion at
///   300 ms. 280 ms is 16.8 frames, which leaves real headroom over the floor
///   rather than sitting two dropped frames away from failing it. Emil also says never animate a
///   keyboard-initiated action — that rule is aimed at actions repeated
///   hundreds of times a day, and it is overridden here deliberately: row 77 is
///   a locked exceeds-source row, the grid toggle is an occasional overview
///   gesture rather than a command-palette open, and the transition's purpose
///   is Emil's own first valid one, spatial consistency. Without it a viewer
///   cannot map a grid card back to its carousel position, which is exactly the
///   defect VIDEO-REVIEW section 2.7 records in all six of the source's hard
///   cuts.
/// * `selectionMove` **140 ms**. Grid selection is arrow-driven and can repeat,
///   so it sits at the fast end of Emil's 150-250 ms band for selects and is
///   retargeted from the presentation value rather than queued.
/// * `toastIn` **330 ms** and `toastDwell` **3.6 s** are measured, from
///   CONTRACT rows 67 and 68.
/// * `toastOut` **200 ms**. CONTRACT row 78 needs at least 8 frames, which is
///   133 ms; Emil requires the exit to be faster than the entrance. 200 ms is
///   12 frames and 0.6 of the entrance.
@MainActor
enum CarouselOverlayMotion {
    static let gridTransition: CFTimeInterval = 0.28
    static let selectionMove: CFTimeInterval = 0.14
    static let toastIn: CFTimeInterval = 0.33
    static let toastDwell: CFTimeInterval = 3.6
    static let toastOut: CFTimeInterval = 0.20

    /// Reduced-motion cross-fade, CONTRACT row 113. Each half is 100 ms, and
    /// geometry only ever changes while opacity is zero.
    static let reducedCrossFade: CFTimeInterval = 0.20
    static var reducedCrossFadeHalf: CFTimeInterval { reducedCrossFade / 2 }

    /// The platform's built-in curves are too weak to read as intentional.
    /// These are Emil's strong variants.
    static var easeOut: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    /// For a morph that starts and ends on screen, which is what the grid
    /// transition is.
    static var easeInOut: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
    }

    /// Injectable so a test can force the reduced-motion path without touching
    /// the machine's accessibility settings. CONTRACT row 113 is asserted
    /// through this seam.
    static var reduceMotionProvider: @MainActor () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static var reduceMotion: Bool { reduceMotionProvider() }

    /// Apple's Designing Fluid Interfaces, section 14: reduced transparency is
    /// an independent signal from reduced motion. Injectable for the same
    /// reason.
    static var reduceTransparencyProvider: @MainActor () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    static var reduceTransparency: Bool { reduceTransparencyProvider() }

    /// Injectable colour-differentiation signal (ruling (d)): when on, status
    /// is carried by shape as well as colour. Injectable for the same reason.
    static var differentiateWithoutColorProvider: @MainActor () -> Bool = {
        NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor
    }

    static var differentiateWithoutColor: Bool { differentiateWithoutColorProvider() }

    /// Restores both providers to the machine's real settings. Tests call this
    /// in teardown so one test cannot leak a forced value into the next.
    static func resetAccessibilityProviders() {
        reduceMotionProvider = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        reduceTransparencyProvider = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
        differentiateWithoutColorProvider = { NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor }
    }
}
