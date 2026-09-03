// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U3, prompt bar / focus / pty routing).

import Foundation

/// Prompt-bar geometry, CONTRACT rows 32, 33 and 34.
///
/// Every value is a ratio of window width anchored to the reference video's
/// 1344-wide logical viewport, per the contract's normalization rule. Nothing
/// here is an absolute pixel count, so the geometry does not void silently when
/// the window is not exactly 1344 wide.
struct CarouselPromptBarMetrics: Equatable {
    /// The reference video's logical viewport width. Every ratio below was read
    /// off a frame at this width (VIDEO-REVIEW §1.4).
    static let referenceWindowWidth: Double = 1344

    // Row 32.
    static let widthRatio: Double = 0.462
    static let heightRatio: Double = 0.0420
    static let cornerRadiusRatio: Double = 0.0164
    // Row 34.
    static let actionButtonDiameterRatio: Double = 0.0260
    static let actionButtonTrailingInsetRatio: Double = 10.5 / referenceWindowWidth
    // Row 33: measured from the *container* bottom, never from the card.
    static let bottomInsetRatio: Double = 34.5 / referenceWindowWidth

    let windowWidth: Double

    init(windowWidth: Double) {
        self.windowWidth = windowWidth
    }

    var width: Double { Self.widthRatio * windowWidth }
    var height: Double { Self.heightRatio * windowWidth }
    var cornerRadius: Double { Self.cornerRadiusRatio * windowWidth }
    var actionButtonDiameter: Double { Self.actionButtonDiameterRatio * windowWidth }
    var actionButtonTrailingInset: Double { Self.actionButtonTrailingInsetRatio * windowWidth }

    /// Row 33. The bar is detached and screen-anchored: this is its distance to
    /// the container's bottom edge, and it is deliberately not a function of
    /// container height or of the card's geometry. A build that anchored the bar
    /// to the card would still satisfy rows 32 and 34 and fail only here.
    var bottomInset: Double { Self.bottomInsetRatio * windowWidth }

    /// Origin y of the bar in a bottom-left coordinate space (AppKit), for a
    /// container of the given height. Constant offset from the bottom edge, so
    /// the returned value moves with the container but the *gap* never changes.
    func originY(inContainerOfHeight containerHeight: Double) -> Double {
        _ = containerHeight
        return bottomInset
    }

    /// Distance from the container's bottom edge to the bar's bottom edge.
    /// Row 33's assertion reads this at three window heights.
    func distanceToContainerBottom(inContainerOfHeight containerHeight: Double) -> Double {
        originY(inContainerOfHeight: containerHeight)
    }

    /// Origin y of the bar in a top-left coordinate space (SwiftUI), for a
    /// container of the given height. Unlike `originY`, this genuinely varies
    /// with the container: the bar hangs `bottomInset` above the bottom edge,
    /// so its distance from the top is the container height minus the bar's
    /// own height minus that gap. The two functions pin opposite halves of
    /// row 33 — this one that placement is computed from the container at
    /// all, `distanceToContainerBottom` that the gap never changes.
    func originYFromTop(inContainerOfHeight containerHeight: Double) -> Double {
        containerHeight - bottomInset - height
    }

    /// The action button is vertically centred in the bar (row 34).
    var actionButtonCentreY: Double { height / 2 }

    /// Leading edge of the action button, measured from the bar's leading edge.
    var actionButtonOriginX: Double {
        width - actionButtonTrailingInset - actionButtonDiameter
    }

    /// Row 32's radius is a rounded rect, not a stadium. VIDEO-REVIEW §1.4
    /// confirms it from a 25-device-pixel straight run along the bar's edge.
    var isStadium: Bool { cornerRadius >= height / 2 }
}
