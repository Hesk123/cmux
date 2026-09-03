// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures a rect of a cmux window as a `CGImage` at backing scale, through the
/// **permission-free current-process ScreenCaptureKit path** (CONTRACT row 115).
///
/// `NSView.cacheDisplay` is the house pattern for view-to-image in six places in
/// this repo and **must not be used here**. It does not composite layer-backed Metal
/// content: the Phase 0 spike measured the same 1520x1288 rect through both paths
/// and found ScreenCaptureKit 99.99 % opaque against `cacheDisplay`'s 0.82 %. The
/// contract says `cacheDisplay` yields "blank or stale flanks"; the spike's
/// correction is sharper and worth carrying, because it changes how a future reader
/// would misjudge it - the result is not blank, it is *transparent*, with about 1 %
/// glyph coverage compositing through. A flank built on it would render text over
/// whatever sits behind the card and could be eyeballed as working.
///
/// Timing, measured by the spike over two runs: cold capture ~74 ms, warm median
/// 11.6 ms, warm p95 15.6 ms, with about 5 % of warm captures over one 60 Hz frame.
/// That is why ``CarouselLiveSwapCoordinator`` never captures on the keypress frame.
enum CarouselCardSnapshotter {
    /// Captures the area `view` occupies, at the window's backing scale.
    ///
    /// Takes the view rather than a rect because the conversion is the part that is
    /// easy to get wrong. ScreenCaptureKit returns an image covering the window's
    /// **content rect**, top-down; AppKit gives view geometry bottom-up relative to
    /// whatever ancestor is asked. Converting into the content view and flipping
    /// against *its* height is the only pairing that holds for a window with a
    /// custom full-size-content titlebar, which is what cmux has. Flipping against
    /// `window.frame.height` instead would land the crop mirrored about the
    /// window's horizontal midline whenever the two differ - and a mirrored crop
    /// reads as "the wrong card", not as a coordinate bug.
    ///
    /// Returns nil rather than a partial image on any failure. A caller that gets
    /// nil keeps the previous cached capture, which is why a dropped capture here is
    /// invisible instead of a flash.
    @MainActor
    static func capture(view: NSView, in window: NSWindow) async -> CGImage? {
        guard let contentView = window.contentView else { return nil }
        let rectInContent = view.convert(view.bounds, to: contentView)
        guard rectInContent.width >= 1, rectInContent.height >= 1 else { return nil }
        let topDown = contentView.isFlipped
            ? rectInContent
            : CGRect(
                x: rectInContent.minX,
                y: contentView.bounds.height - rectInContent.maxY,
                width: rectInContent.width,
                height: rectInContent.height
            )
        return await captureImage(
            windowID: CGWindowID(window.windowNumber),
            topDownRect: topDown
        )
    }

    private nonisolated static func captureImage(
        windowID: CGWindowID,
        topDownRect: CGRect
    ) async -> CGImage? {
        do {
            let content: SCShareableContent
            if #available(macOS 14.4, *) {
                // Current-process-only: captures cmux's own windows without ever
                // asking for Screen Recording permission.
                content = try await SCShareableContent.currentProcess
            } else {
                // macOS 14.0-14.3 has no permission-free current-process query. The
                // older inventory is used solely to locate our own window id.
                content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
            }
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let info = SCShareableContent.info(for: filter)
            let scale = CGFloat(info.pointPixelScale)

            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int((info.contentRect.width * scale).rounded()))
            configuration.height = max(1, Int((info.contentRect.height * scale).rounded()))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .best

            let full = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )

            // `topDownRect` is already in the image's orientation; only the point
            // to pixel scaling is left.
            let cropInPixels = CGRect(
                x: topDownRect.minX * scale,
                y: topDownRect.minY * scale,
                width: topDownRect.width * scale,
                height: topDownRect.height * scale
            ).integral
            let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
            let clamped = cropInPixels.intersection(bounds)
            guard !clamped.isNull, clamped.width >= 1, clamped.height >= 1 else { return nil }
            return full.cropping(to: clamped)
        } catch {
            return nil
        }
    }
}
