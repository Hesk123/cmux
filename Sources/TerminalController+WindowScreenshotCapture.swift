import AppKit
import Foundation
import ScreenCaptureKit
import WebKit

#if DEBUG
extension TerminalController {
    nonisolated func captureScreenshot(_ args: String) -> String {
        guard !Thread.isMainThread else {
            return "ERROR: screenshot must run off the main thread"
        }

        // Phase 0 carousel capture spike (throwaway, branch spike/capture).
        if args.hasPrefix("spike") {
            return runCaptureSpike(String(args.dropFirst("spike".count)))
        }

        // Parse optional label from args
        let label = WindowScreenshotLabel(args).value

        // Generate unique ID for this screenshot
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "+", with: "_")
        let shortId = UUID().uuidString.prefix(8)
        let screenshotId = "\(timestamp)_\(shortId)"

        // Determine output path
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-screenshots")
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let filename = label.isEmpty ? "\(screenshotId).png" : "\(label)_\(screenshotId).png"
        let outputPath = outputDir.appendingPathComponent(filename)

        let captureTarget: CGWindowID? = v2MainSync {
            let candidateWindows = NSApp.windows.filter { window in
                window.isVisible &&
                    !window.isMiniaturized &&
                    window.contentView != nil &&
                    !window.frame.isEmpty
            }
            let window = WindowScreenshotWindowSelector.select(
                eligibleWindows: candidateWindows,
                keyWindow: NSApp.keyWindow,
                mainWindow: NSApp.mainWindow,
                terminalWindow: self.tabManager?.window
            )
            guard let window else { return nil }
            return WindowScreenshotTarget(
                windowNumber: window.windowNumber
            )?.windowID
        }
        guard let captureTarget else {
            return "ERROR: No window available"
        }

        // Prefer the system compositor when policy permits it, and avoid the
        // heavier main-actor fallback on the normal path. Independent backend
        // admission keeps a stalled compositor from accumulating more work or
        // blocking the permission-free AppKit fallback.
        let screenCaptureKitAttempt = captureScreenCaptureKitWindowPNGData(
            captureTarget
        )
        let pngData: Data
        if let captured = screenCaptureKitAttempt.capturedValue {
            pngData = captured
        } else {
            let appKitAttempt = captureAppKitWindowPNGData(captureTarget)
            guard let captured = appKitAttempt.capturedValue else {
                if appKitAttempt.isBusy || screenCaptureKitAttempt.isBusy {
                    return "ERROR: screenshot capture already in progress"
                }
                if appKitAttempt.didTimeOut || screenCaptureKitAttempt.didTimeOut {
                    return "ERROR: screenshot capture timed out"
                }
                return "ERROR: Failed to create PNG data"
            }
            pngData = captured.pngData
        }

        do {
            try pngData.write(to: outputPath)
        } catch {
            return "ERROR: Failed to write file: \(error.localizedDescription)"
        }

        // Return OK with screenshot ID and path for easy reference
        return "OK \(screenshotId) \(outputPath.path)"
    }

    private nonisolated func captureScreenCaptureKitWindowPNGData(
        _ windowID: CGWindowID
    ) -> WindowScreenshotBackendAttempt<Data> {
        guard Self.screenCaptureKitMayRunWithoutPrompt else {
            return .unavailable
        }
        guard let captureLease = windowScreenshotCaptureCoordinator
            .claimScreenCaptureKit() else {
            return .busy
        }
        let captureTask = Task {
            defer { captureLease.retire() }
            return await Self.captureScreenCaptureKitWindowPNGDataAsync(windowID)
        }
        let captured: Data?? = socketAwaitCallback(timeout: 5) { completion in
            Task {
                completion(await captureTask.value)
            }
        }
        guard let captured else {
            captureTask.cancel()
            return .timedOut
        }
        guard let captured else { return .unavailable }
        return .captured(captured)
    }

    private nonisolated static var screenCaptureKitMayRunWithoutPrompt: Bool {
        if #available(macOS 14.4, *) {
            return WindowScreenshotScreenCapturePolicy(
                currentProcessAPIAvailable: true,
                screenCaptureAccessGranted: false
            ).allowsScreenCaptureKit
        }
        return WindowScreenshotScreenCapturePolicy(
            currentProcessAPIAvailable: false,
            screenCaptureAccessGranted: CGPreflightScreenCaptureAccess()
        ).allowsScreenCaptureKit
    }

    private nonisolated static func captureScreenCaptureKitWindowPNGDataAsync(
        _ windowID: CGWindowID
    ) async -> Data? {
        do {
            let shareableContent: SCShareableContent
            if #available(macOS 14.4, *) {
                // This current-process-only query captures cmux's own windows
                // without requesting Screen Recording permission.
                shareableContent = try await SCShareableContent.currentProcess
            } else {
                // macOS 14.0–14.3 lacks the permission-free current-process
                // query. Use the older ScreenCaptureKit inventory solely to
                // locate our exact window ID; denial falls back to AppKit.
                shareableContent = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
            }
            guard let window = shareableContent.windows.first(where: {
                $0.windowID == windowID
            }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let contentInfo = SCShareableContent.info(for: filter)
            let scale = CGFloat(contentInfo.pointPixelScale)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(ceil(contentInfo.contentRect.width * scale)))
            configuration.height = max(1, Int(ceil(contentInfo.contentRect.height * scale)))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .best

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return NSBitmapImageRep(cgImage: image).representation(
                using: .png,
                properties: [:]
            )
        } catch {
            return nil
        }
    }

    private nonisolated func captureAppKitWindowPNGData(
        _ windowID: CGWindowID
    ) -> WindowScreenshotBackendAttempt<WindowAppKitCapture> {
        guard let captureLease = windowScreenshotCaptureCoordinator
            .claimAppKit() else {
            return .busy
        }
        let captureTask = Task { @MainActor in
            defer { captureLease.retire() }
            return await self.captureAppKitWindowPNGDataOnMain(windowID)
        }
        let captured: WindowAppKitCapture?? = socketAwaitCallback(
            timeout: 5
        ) { completion in
            Task {
                completion(await captureTask.value)
            }
        }
        guard let captured else {
            captureTask.cancel()
            return .timedOut
        }
        guard let captured else { return .unavailable }
        return .captured(captured)
    }

    @MainActor
    private func captureAppKitWindowPNGDataOnMain(
        _ windowID: CGWindowID
    ) async -> WindowAppKitCapture? {
        guard let window = NSApp.windows.first(where: {
            WindowScreenshotTarget(windowNumber: $0.windowNumber)?.windowID
                == windowID
        }) else {
            return nil
        }
        return await captureAppKitWindowPNGData(window)
    }

    private func captureAppKitWindowPNGData(_ window: NSWindow) async -> WindowAppKitCapture? {
        guard !Task.isCancelled else { return nil }
        // Every WebKit request consumes from one aggregate fallback budget so
        // this independently leased backend responds promptly to cancellation.
        let captureDeadline = ProcessInfo.processInfo.systemUptime + 4
        guard let captureRoot = WindowAppKitCapture.rootView(for: window) else {
            return nil
        }

        let bounds = captureRoot.bounds
        guard !bounds.isEmpty,
              let bitmap = captureRoot.bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        bitmap.size = bounds.size

        captureRoot.displayIfNeeded()
        captureRoot.cacheDisplay(in: bounds, to: bitmap)
        guard !Task.isCancelled else { return nil }

        var overlays: [WindowScreenshotOverlay] = []
        var capturedOccludingViews = Set<ObjectIdentifier>()

        for terminalView in visibleDescendants(of: captureRoot, as: GhosttySurfaceScrollView.self) {
            guard !Task.isCancelled else { return nil }
            guard let clipRect = WindowAppKitCapture.visibleRect(
                of: terminalView.surfaceView,
                through: captureRoot
            ) else {
                continue
            }
            guard let image = terminalView.debugCopyIOSurfaceCGImage() else {
                continue
            }
            let rect = terminalView.surfaceView.convert(
                terminalView.surfaceView.bounds,
                to: captureRoot
            )
            guard !rect.isEmpty else { continue }
            let alpha = effectiveAlpha(of: terminalView.surfaceView, through: captureRoot)
            guard alpha > 0 else { continue }
            guard let zOrder = hierarchyZOrder(of: terminalView.surfaceView, through: captureRoot) else {
                continue
            }
            overlays.append(WindowScreenshotOverlay(
                image: image,
                rect: rect,
                clipRect: clipRect,
                alpha: alpha,
                zOrder: zOrder
            ))
            appendNativeDescendantOverlays(
                inside: terminalView.surfaceView,
                through: captureRoot,
                capturedViews: &capturedOccludingViews,
                to: &overlays
            )
            appendNativeOccluderOverlays(
                above: terminalView.surfaceView,
                through: captureRoot,
                overlapping: rect,
                capturedViews: &capturedOccludingViews,
                to: &overlays
            )
        }

        for webView in visibleDescendants(of: captureRoot, as: WKWebView.self) {
            guard !Task.isCancelled else { return nil }
            guard let clipRect = WindowAppKitCapture.visibleRect(
                of: webView,
                through: captureRoot
            ) else {
                continue
            }
            let remainingBudget =
                captureDeadline - ProcessInfo.processInfo.systemUptime
            guard remainingBudget > 0 else { break }
            do {
                let image = try await BrowserScreenshotWebViewSnapshotter.captureVisibleViewport(
                    from: webView,
                    timeout: min(2, remainingBudget)
                )
                guard !Task.isCancelled else { return nil }
                var proposedRect = NSRect(origin: .zero, size: image.size)
                guard let cgImage = image.cgImage(
                    forProposedRect: &proposedRect,
                    context: nil,
                    hints: nil
                ) else {
                    continue
                }
                let rect = webView.convert(webView.bounds, to: captureRoot)
                guard !rect.isEmpty else { continue }
                let alpha = effectiveAlpha(of: webView, through: captureRoot)
                guard alpha > 0 else { continue }
                guard let zOrder = hierarchyZOrder(of: webView, through: captureRoot) else {
                    continue
                }
                overlays.append(WindowScreenshotOverlay(
                    image: cgImage,
                    rect: rect,
                    clipRect: clipRect,
                    alpha: alpha,
                    zOrder: zOrder
                ))
                for overlayView in WindowAppKitCapture.ownedNativeOverlayCandidates(
                    inside: webView
                ) {
                    appendNativeOverlay(
                        overlayView,
                        through: captureRoot,
                        capturedViews: &capturedOccludingViews,
                        to: &overlays
                    )
                }
                appendNativeOccluderOverlays(
                    above: webView,
                    through: captureRoot,
                    overlapping: rect,
                    capturedViews: &capturedOccludingViews,
                    to: &overlays
                )
            } catch is CancellationError {
                return nil
            } catch {
                continue
            }
        }

        guard !Task.isCancelled else { return nil }
        guard let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }
        let context = graphicsContext.cgContext
        context.saveGState()
        context.interpolationQuality = .high
        context.clip(
            to: NSRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: bounds.height
            )
        )
        for overlay in overlays.sorted(by: { hierarchyZOrderPrecedes($0.zOrder, $1.zOrder) }) {
            guard overlay.clipRect.intersects(bounds) else { continue }
            context.saveGState()
            context.setAlpha(overlay.alpha)
            let destinationRect = windowScreenshotBitmapRect(
                for: overlay.rect,
                within: bounds,
                sourceIsFlipped: captureRoot.isFlipped
            )
            let destinationClipRect = windowScreenshotBitmapRect(
                for: overlay.clipRect,
                within: bounds,
                sourceIsFlipped: captureRoot.isFlipped
            )
            context.clip(to: destinationClipRect)
            context.draw(overlay.image, in: destinationRect)
            context.restoreGState()
        }
        context.restoreGState()

        guard !Task.isCancelled else { return nil }
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return WindowAppKitCapture(pngData: pngData)
    }

    private func visibleDescendants<T: NSView>(
        of root: NSView,
        as type: T.Type
    ) -> [T] {
        var matches: [T] = []
        var pending = root.subviews
        while let view = pending.popLast() {
            guard !view.isHiddenOrHasHiddenAncestor, view.alphaValue > 0 else {
                continue
            }
            if let match = view as? T {
                matches.append(match)
                continue
            }
            pending.append(contentsOf: view.subviews)
        }
        return matches
    }

    private func appendNativeDescendantOverlays(
        inside externalView: NSView,
        through root: NSView,
        capturedViews: inout Set<ObjectIdentifier>,
        to overlays: inout [WindowScreenshotOverlay]
    ) {
        for subview in WindowAppKitCapture.nativeOverlayCandidates(
            inside: externalView
        ) {
            appendNativeOverlay(
                subview,
                through: root,
                capturedViews: &capturedViews,
                to: &overlays
            )
        }
    }

    private func appendNativeOccluderOverlays(
        above externalView: NSView,
        through root: NSView,
        overlapping externalRect: NSRect,
        capturedViews: inout Set<ObjectIdentifier>,
        to overlays: inout [WindowScreenshotOverlay]
    ) {
        var current = externalView

        while current !== root {
            guard let parent = current.superview,
                  let index = parent.subviews.firstIndex(where: { $0 === current }) else {
                return
            }

            for sibling in parent.subviews.dropFirst(index + 1) {
                let rect = sibling.convert(sibling.bounds, to: root)
                guard !rect.isEmpty, rect.intersects(externalRect) else { continue }
                appendNativeOverlay(
                    sibling,
                    through: root,
                    capturedViews: &capturedViews,
                    to: &overlays
                )
            }
            current = parent
        }
    }

    private func appendNativeOverlay(
        _ view: NSView,
        through root: NSView,
        capturedViews: inout Set<ObjectIdentifier>,
        to overlays: inout [WindowScreenshotOverlay]
    ) {
        guard !view.isHiddenOrHasHiddenAncestor,
              view.alphaValue > 0,
              !WindowAppKitCapture.containsSystemCompositorContent(in: view),
              let clipRect = WindowAppKitCapture.visibleRect(of: view, through: root) else {
            return
        }
        let identifier = ObjectIdentifier(view)
        guard capturedViews.insert(identifier).inserted,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return
        }
        bitmap.size = view.bounds.size
        view.displayIfNeeded()
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return }
        let rect = view.convert(view.bounds, to: root)
        let alpha = effectiveAlpha(of: view, through: root)
        guard !rect.isEmpty,
              alpha > 0,
              let zOrder = hierarchyZOrder(of: view, through: root) else {
            return
        }
        overlays.append(WindowScreenshotOverlay(
            image: image,
            rect: rect,
            clipRect: clipRect,
            alpha: alpha,
            zOrder: zOrder
        ))
    }

    private func windowScreenshotBitmapRect(
        for rect: NSRect,
        within bounds: NSRect,
        sourceIsFlipped: Bool
    ) -> NSRect {
        if sourceIsFlipped {
            return NSRect(
                x: rect.minX - bounds.minX,
                y: bounds.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
        }
        return NSRect(
            x: rect.minX - bounds.minX,
            y: rect.minY - bounds.minY,
            width: rect.width,
            height: rect.height
        )
    }

    private func hierarchyZOrder(of view: NSView, through root: NSView) -> [Int]? {
        var reversedPath: [Int] = []
        var current = view
        while current !== root {
            guard let parent = current.superview,
                  let index = parent.subviews.firstIndex(where: { $0 === current }) else {
                return nil
            }
            reversedPath.append(index)
            current = parent
        }
        return Array(reversedPath.reversed())
    }

    private func hierarchyZOrderPrecedes(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left < right
        }
        return lhs.count < rhs.count
    }

    private func effectiveAlpha(of view: NSView, through root: NSView) -> CGFloat {
        var alpha: CGFloat = 1
        var current: NSView? = view
        while let candidate = current {
            alpha *= candidate.alphaValue
            if candidate === root {
                return alpha
            }
            current = candidate.superview
        }
        return 0
    }
}
#endif

// MARK: - Phase 0 carousel capture spike (THROWAWAY — branch spike/capture)
//
// Proves CONTRACT rows 115 and 135, plan Phase 0 steps 3-5:
//   * a live libghostty Metal surface can be captured through the
//     permission-free current-process ScreenCaptureKit query,
//   * at the display backing scale,
//   * fast enough to feed flank snapshot layers,
//   * that `cacheDisplay` on the SAME surface cannot reproduce that content —
//     the negative control that makes the positive result mean anything,
//   * and that the captured image, in a CALayer scaled to 0.94 and translated
//     by one pitch, sustains the display cadence under plain CA transforms.
//
// Reached as `screenshot spike [iterations]`, so it inherits the existing
// socket-worker lane: `screenshot` is already in `socketWorkerV1Commands`.
// Not product code. Delete with the branch.

#if DEBUG
import QuartzCore

struct CarouselSpikeImageStats {
    var meanLuminance: Double
    var stdDevLuminance: Double
    var populatedBuckets: Int
    var nonModalFraction: Double
    var pixelWidth: Int
    var pixelHeight: Int
    var opaqueFraction: Double
    var meanAlpha: Double

    var line: String {
        String(
            format: "%dx%dpx  mean=%6.2f  stddev=%6.2f  buckets=%2d/64  nonModal=%.4f  opaque=%.4f  meanAlpha=%5.1f",
            pixelWidth, pixelHeight, meanLuminance, stdDevLuminance,
            populatedBuckets, nonModalFraction, opaqueFraction, meanAlpha
        )
    }

    /// A capture that reproduced terminal content has real tonal spread. A
    /// blank or black Metal capture collapses toward one bucket with ~zero
    /// spread. Thresholds are deliberately loose: the claim being tested is
    /// "content vs no content", not a fidelity measurement.
    /// Alpha coverage first: a capture that missed the Metal layer comes back
    /// almost entirely transparent, and a transparent pixel reads as black,
    /// which luminance cannot distinguish from a legitimately dark terminal.
    var looksLikeRealContent: Bool {
        opaqueFraction >= 0.90 && stdDevLuminance >= 3.0 && populatedBuckets >= 4
    }
}

func carouselSpikeImageStats(_ image: CGImage) -> CarouselSpikeImageStats? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else { return nil }
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    let drew: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
        guard let context = CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drew else { return nil }

    var histogram = [Int](repeating: 0, count: 64)
    var sum = 0.0
    var sumSquares = 0.0
    var alphaSum = 0.0
    var opaqueCount = 0
    let pixelCount = width * height
    var index = 0
    while index < pixels.count {
        let luminance = 0.2126 * Double(pixels[index])
            + 0.7152 * Double(pixels[index + 1])
            + 0.0722 * Double(pixels[index + 2])
        sum += luminance
        sumSquares += luminance * luminance
        histogram[min(63, Int(luminance) / 4)] += 1
        let alpha = pixels[index + 3]
        alphaSum += Double(alpha)
        if alpha >= 250 { opaqueCount += 1 }
        index += 4
    }
    let mean = sum / Double(pixelCount)
    let variance = max(0, sumSquares / Double(pixelCount) - mean * mean)
    let modal = histogram.max() ?? pixelCount
    return CarouselSpikeImageStats(
        meanLuminance: mean,
        stdDevLuminance: variance.squareRoot(),
        populatedBuckets: histogram.reduce(into: 0) { if $1 > 0 { $0 += 1 } },
        nonModalFraction: 1.0 - Double(modal) / Double(pixelCount),
        pixelWidth: width,
        pixelHeight: height,
        opaqueFraction: Double(opaqueCount) / Double(pixelCount),
        meanAlpha: alphaSum / Double(pixelCount)
    )
}
#endif

#if DEBUG
/// Drives a three-card snapshot track through repeated carousel switches on a
/// real display link, recording every frame timestamp so dropped frames are
/// counted from the frame record rather than asserted.
@MainActor
final class CarouselSpikeLayerDriver: NSObject {
    /// The socket worker returns as soon as the run completes, so the driver
    /// needs an owner for the duration of the run.
    static var retained: CarouselSpikeLayerDriver?

    private let window: NSWindow
    private let track = CALayer()
    private var link: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private var startTime: CFTimeInterval = 0
    private let frameBudget: Int
    private let pitch: CGFloat
    private var finish: (([CFTimeInterval]) -> Void)?

    let windowSize: CGSize
    let cardSize: CGSize

    init(image: CGImage, backingScale: CGFloat, frameBudget: Int) {
        self.frameBudget = frameBudget

        // CONTRACT row 9: the TARGET centre card is 0.720 x 0.566 of W, i.e.
        // 968 x 761 CSS at the row-17 fidelity window W = 1344. (848 x 667 is
        // the SOURCE video's card, which is not what this build renders.)
        // D-13 gap 55, D-2 side scale 0.94 give the row-25 pitch 993.96,
        // which row 52 independently states as the switch displacement.
        let card = CGSize(width: 968, height: 761)
        self.cardSize = card
        self.pitch = card.width / 2 + 55 + (card.width * 0.94) / 2

        // The contract fidelity window is 1344 x 1080; plan § 17.4 warns it may
        // not fit the display, so clamp and report what was actually used.
        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1344, height: 1080)
        let size = CGSize(
            width: min(1344, visible.width - 40),
            height: min(1080, visible.height - 40)
        )
        self.windowSize = size

        window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: 20, y: 20), size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "carousel capture spike"
        super.init()

        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = host
        guard let hostLayer = host.layer else { return }
        hostLayer.addSublayer(track)
        track.frame = host.bounds
        track.masksToBounds = true

        for offset in -1...1 {
            let cardLayer = CALayer()
            cardLayer.contents = image
            cardLayer.contentsGravity = .resizeAspectFill
            cardLayer.contentsScale = backingScale
            cardLayer.bounds = CGRect(origin: .zero, size: card)
            cardLayer.position = CGPoint(
                x: host.bounds.midX + CGFloat(offset) * pitch,
                y: host.bounds.midY
            )
            cardLayer.masksToBounds = true
            cardLayer.cornerRadius = 12
            // D-2: flanks at 0.94, centre live-equivalent at 1.0.
            if offset != 0 {
                cardLayer.transform = CATransform3DMakeScale(0.94, 0.94, 1)
            }
            track.addSublayer(cardLayer)
        }
    }

    func run(_ completion: @escaping ([CFTimeInterval]) -> Void) {
        finish = completion
        window.orderFrontRegardless()
        guard let host = window.contentView else {
            completion([])
            return
        }
        let displayLink = host.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
        startTime = CACurrentMediaTime()
    }

    @objc private func tick(_ sender: CADisplayLink) {
        frameTimestamps.append(sender.timestamp)

        // One 300 ms switch (row 52) looped, carrying the row-54 recoil so the
        // track transform actually changes every frame instead of resting.
        let elapsed = CACurrentMediaTime() - startTime
        let progress = elapsed.truncatingRemainder(dividingBy: 0.3) / 0.3
        let eased = progress * progress * (3 - 2 * progress)
        let recoilPhase = min(1.0, progress / 0.6)
        let recoil = 1.0 - 0.029 * sin(recoilPhase * .pi)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var transform = CATransform3DMakeTranslation(-pitch * CGFloat(eased), 0, 0)
        transform = CATransform3DScale(transform, CGFloat(recoil), CGFloat(recoil), 1)
        track.transform = transform
        CATransaction.commit()

        guard frameTimestamps.count >= frameBudget else { return }
        sender.invalidate()
        link = nil
        window.orderOut(nil)
        let samples = frameTimestamps
        frameTimestamps = []
        let completion = finish
        finish = nil
        completion?(samples)
    }
}
#endif

#if DEBUG
struct CarouselSpikeTarget {
    var windowID: CGWindowID
    var backingScale: CGFloat
    var surfaceRectInWindow: CGRect
    var surfaceDescription: String
}

struct CarouselSpikeSCKRun {
    var timingsMs: [Double] = []
    var image: CGImage?
    var pointPixelScale: Double = 0
    var contentRectPoints: CGRect = .zero
    var failure: String?
}

private func carouselSpikePercentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
    return sorted[index]
}

extension TerminalController {
    /// Phase 0 kill-shot. See the file-level spike comment.
    nonisolated func runCaptureSpike(_ args: String) -> String {
        let iterations = max(1, Int(args.trimmingCharacters(in: .whitespaces)) ?? 40)
        var out: [String] = []
        out.append("=== carousel capture spike — CONTRACT rows 115 / 135 ===")
        out.append("iterations=\(iterations)")

        // ---- Resolve the window and the live ghostty surface inside it ----
        // Scan EVERY window rather than trusting the screenshot selector: the
        // terminal lives under the portal's WindowTerminalHostView, and which
        // window owns it is exactly what this spike must not assume.
        struct CarouselSpikeScan {
            var inventory: [String] = []
            var target: CarouselSpikeTarget?
        }
        let scan: CarouselSpikeScan = v2MainSync {
            @MainActor
            func firstSurface(_ view: NSView) -> GhosttySurfaceScrollView? {
                if let surface = view as? GhosttySurfaceScrollView { return surface }
                for subview in view.subviews {
                    if let found = firstSurface(subview) { return found }
                }
                return nil
            }
            @MainActor
            func countSurfaces(_ view: NSView) -> Int {
                var total = (view is GhosttySurfaceScrollView) ? 1 : 0
                for subview in view.subviews { total += countSurfaces(subview) }
                return total
            }

            var result = CarouselSpikeScan()
            for window in NSApp.windows {
                // WindowContentOverlayTargetResolver installs the terminal
                // portal into the glass target or the theme frame BELOW
                // contentView, so scanning from contentView finds nothing.
                let root = window.contentView?.superview ?? window.contentView
                let surfaces = root.map(countSurfaces) ?? 0
                result.inventory.append(
                    "  win#\(window.windowNumber) \(type(of: window)) "
                    + "visible=\(window.isVisible) mini=\(window.isMiniaturized) "
                    + "frame=\(Int(window.frame.width))x\(Int(window.frame.height)) "
                    + "surfaces=\(surfaces) title=\u{22}\(window.title)\u{22}"
                )
                guard result.target == nil,
                      window.isVisible, !window.isMiniaturized,
                      surfaces > 0,
                      let searchRoot = root,
                      let surface = firstSurface(searchRoot),
                      let windowID = WindowScreenshotTarget(
                          windowNumber: window.windowNumber
                      )?.windowID
                else { continue }
                result.target = CarouselSpikeTarget(
                    windowID: windowID,
                    backingScale: window.backingScaleFactor,
                    surfaceRectInWindow: surface.convert(surface.bounds, to: nil),
                    surfaceDescription:
                        "\(type(of: surface)) bounds=\(Int(surface.bounds.width))x\(Int(surface.bounds.height))pt"
                        + " hidden=\(surface.isHidden) inWindow=\(surface.window != nil)"
                        + " totalSurfacesInWindow=\(surfaces)"
                )
            }
            return result
        }
        out.append("window inventory (\(scan.inventory.count) windows):")
        out.append(contentsOf: scan.inventory)
        guard let target = scan.target else {
            return (out + ["ERROR: no visible window contains a GhosttySurfaceScrollView"])
                .joined(separator: "\n")
        }
        out.append("chosen window=\(target.windowID) backingScale=\(target.backingScale)")
        out.append("surface=\(target.surfaceDescription) rectInWindow=\(target.surfaceRectInWindow)")

        // ---- A. The kill-shot: permission-free current-process ScreenCaptureKit ----
        let sck: CarouselSpikeSCKRun? = socketAwaitCallback(timeout: 180) { completion in
            Task {
                completion(
                    await Self.runCarouselSpikeSCKCaptures(
                        windowID: target.windowID,
                        iterations: iterations
                    )
                )
            }
        }
        guard let sck else { return "ERROR: ScreenCaptureKit spike timed out" }
        if let failure = sck.failure, sck.image == nil {
            out.append("SCK: FAILED — \(failure)")
            return out.joined(separator: "\n")
        }
        if let failure = sck.failure {
            out.append("SCK: partial — \(failure)")
        }
        let timings = sck.timingsMs
        out.append("")
        out.append("--- A. ScreenCaptureKit current-process capture ---")
        out.append("pointPixelScale=\(sck.pointPixelScale) contentRect=\(sck.contentRectPoints)")
        out.append(String(
            format: "capture ms: first=%.2f  min=%.2f  median=%.2f  p95=%.2f  max=%.2f  n=%d",
            timings.first ?? .nan,
            timings.min() ?? .nan,
            carouselSpikePercentile(timings, 0.5),
            carouselSpikePercentile(timings, 0.95),
            timings.max() ?? .nan,
            timings.count
        ))
        let warm = Array(timings.dropFirst())
        if !warm.isEmpty {
            out.append(String(
                format: "warm (excl. first): median=%.2f  p95=%.2f  under16ms=%d/%d",
                carouselSpikePercentile(warm, 0.5),
                carouselSpikePercentile(warm, 0.95),
                warm.filter { $0 < 16.0 }.count,
                warm.count
            ))
        }

        guard let sckImage = sck.image else {
            out.append("SCK: no image returned")
            return out.joined(separator: "\n")
        }
        let sckStats = carouselSpikeImageStats(sckImage)
        out.append("SCK full-window stats: \(sckStats?.line ?? "unavailable")")
        out.append("SCK content verdict: \(sckStats?.looksLikeRealContent == true ? "REAL CONTENT" : "BLANK/FLAT")")

        // Crop the same surface rect out of the SCK capture so the negative
        // control below compares like with like, not window against view.
        let scale = CGFloat(sck.pointPixelScale)
        let rect = target.surfaceRectInWindow
        let contentHeight = sck.contentRectPoints.height
        let cropRect = CGRect(
            x: rect.origin.x * scale,
            y: (contentHeight - rect.origin.y - rect.height) * scale,
            width: rect.width * scale,
            height: rect.height * scale
        ).intersection(CGRect(x: 0, y: 0, width: sckImage.width, height: sckImage.height))
        var sckCropStats: CarouselSpikeImageStats?
        if !cropRect.isEmpty, let cropped = sckImage.cropping(to: cropRect) {
            sckCropStats = carouselSpikeImageStats(cropped)
            out.append("SCK surface-rect crop: \(sckCropStats?.line ?? "unavailable")")
            Self.writeCarouselSpikePNG(cropped, name: "sck-surface-crop", into: &out)
        } else {
            out.append("SCK surface-rect crop: unavailable (crop=\(cropRect))")
        }
        Self.writeCarouselSpikePNG(sckImage, name: "sck-window", into: &out)

        // ---- B. Negative control: cacheDisplay on the SAME live surface ----
        out.append("")
        out.append("--- B. Negative control: NSView.cacheDisplay on the same surface ---")
        let controlImage: CGImage? = v2MainSync {
            guard let controlWindow = NSApp.windows.first(where: {
                WindowScreenshotTarget(windowNumber: $0.windowNumber)?.windowID == target.windowID
            }),
                let contentView = controlWindow.contentView?.superview
                    ?? controlWindow.contentView
            else { return nil }
            @MainActor
            func firstSurface(_ view: NSView) -> GhosttySurfaceScrollView? {
                if let surface = view as? GhosttySurfaceScrollView { return surface }
                for subview in view.subviews {
                    if let found = firstSurface(subview) { return found }
                }
                return nil
            }
            guard let surface = firstSurface(contentView) else { return nil }
            let bounds = surface.bounds
            guard !bounds.isEmpty,
                  let bitmap = surface.bitmapImageRepForCachingDisplay(in: bounds)
            else { return nil }
            bitmap.size = bounds.size
            surface.displayIfNeeded()
            surface.cacheDisplay(in: bounds, to: bitmap)
            return bitmap.cgImage
        }
        if let controlImage {
            let controlStats = carouselSpikeImageStats(controlImage)
            out.append("cacheDisplay stats: \(controlStats?.line ?? "unavailable")")
            out.append("cacheDisplay verdict: \(controlStats?.looksLikeRealContent == true ? "REAL CONTENT" : "BLANK/FLAT")")
            Self.writeCarouselSpikePNG(controlImage, name: "cachedisplay-surface", into: &out)
            if let sckCropStats, let controlStats {
                let ratio = controlStats.stdDevLuminance / max(0.0001, sckCropStats.stdDevLuminance)
                out.append(String(
                    format: "contrast (same rect): SCK stddev=%.2f vs cacheDisplay stddev=%.2f  ratio=%.4f",
                    sckCropStats.stdDevLuminance, controlStats.stdDevLuminance, ratio
                ))
            }
        } else {
            out.append("cacheDisplay: produced no image at all")
        }

        // ---- C. CALayer at 0.94, translated, on a real display link ----
        out.append("")
        out.append("--- C. CALayer track: 3 cards, flanks 0.94, translate + recoil ---")
        let visibleFrame: CGRect = v2MainSync { NSScreen.main?.visibleFrame ?? .zero }
        out.append("screen visibleFrame=\(visibleFrame) — the spike window is clamped into it")
        let frameBudget = 240
        let samples: [CFTimeInterval]? = socketAwaitCallback(timeout: 60) { completion in
            Task { @MainActor in
                let driver = CarouselSpikeLayerDriver(
                    image: sckImage,
                    backingScale: target.backingScale,
                    frameBudget: frameBudget
                )
                CarouselSpikeLayerDriver.retained = driver
                driver.run { frames in
                    CarouselSpikeLayerDriver.retained = nil
                    completion(frames)
                }
            }
        }
        if let samples, samples.count > 2 {
            var intervals: [Double] = []
            for index in 1..<samples.count {
                intervals.append((samples[index] - samples[index - 1]) * 1000)
            }
            let nominal = carouselSpikePercentile(intervals, 0.5)
            let dropped = intervals.filter { $0 > nominal * 1.5 }.count
            out.append(String(
                format: "frames=%d  nominal=%.3f ms (%.1f Hz)  mean=%.3f  p95=%.3f  max=%.3f",
                samples.count, nominal, 1000 / nominal,
                intervals.reduce(0, +) / Double(intervals.count),
                carouselSpikePercentile(intervals, 0.95),
                intervals.max() ?? .nan
            ))
            out.append("dropped frames (interval > 1.5x nominal): \(dropped)/\(intervals.count)")
        } else {
            out.append("display-link run produced no usable frame record")
        }

        out.append("")
        out.append("=== end spike ===")
        return out.joined(separator: "\n")
    }

    fileprivate nonisolated static func writeCarouselSpikePNG(
        _ image: CGImage,
        name: String,
        into out: inout [String]
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-carousel-spike")
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent("\(name).png")
        guard let data = NSBitmapImageRep(cgImage: image).representation(
            using: .png, properties: [:]
        ) else {
            out.append("PNG \(name): encode failed")
            return
        }
        do {
            try data.write(to: url)
            out.append("PNG \(name): \(url.path)")
        } catch {
            out.append("PNG \(name): write failed \(error.localizedDescription)")
        }
    }

    fileprivate nonisolated static func runCarouselSpikeSCKCaptures(
        windowID: CGWindowID,
        iterations: Int
    ) async -> CarouselSpikeSCKRun {
        var run = CarouselSpikeSCKRun()
        do {
            let content: SCShareableContent
            if #available(macOS 14.4, *) {
                // The permission-free query the contract names.
                content = try await SCShareableContent.currentProcess
            } else {
                run.failure = "macOS < 14.4 — current-process query unavailable"
                return run
            }
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                run.failure = "window \(windowID) absent from currentProcess inventory"
                return run
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let info = SCShareableContent.info(for: filter)
            let scale = CGFloat(info.pointPixelScale)
            run.pointPixelScale = Double(info.pointPixelScale)
            run.contentRectPoints = info.contentRect

            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(ceil(info.contentRect.width * scale)))
            configuration.height = max(1, Int(ceil(info.contentRect.height * scale)))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            configuration.captureResolution = .best

            for _ in 0..<iterations {
                let began = DispatchTime.now().uptimeNanoseconds
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
                let ended = DispatchTime.now().uptimeNanoseconds
                run.timingsMs.append(Double(ended - began) / 1_000_000)
                run.image = image
            }
        } catch {
            run.failure = "\(error)"
        }
        return run
    }
}
#endif
