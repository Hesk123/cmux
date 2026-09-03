// Added 2026-09-02 for the cmux carousel UI build, unit U6.
// CONTRACT rows 77, 80, 83, 112 (grid-toggle half), 113 (grid half).
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
final class CarouselGridTransitionTests: XCTestCase {
    private var window: NSWindow!
    private var host: CarouselOverlayHostView!
    private var track: CALayer!
    private var cardLayers: [CALayer] = []
    private var presenter: CarouselGridPresenter!
    private var geometry: CarouselOverlayGeometry!
    private let recorder = CarouselOverlayFrameRecorder()

    private static let viewport = CGSize(width: 1_344, height: 1_080)

    override func setUp() async throws {
        try await super.setUp()
        geometry = CarouselOverlayGeometry.contractDefault(viewport: Self.viewport)

        window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.viewport),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        host = CarouselOverlayHostView(frame: CGRect(origin: .zero, size: Self.viewport))
        window.contentView = host
        window.orderFront(nil)

        // U1 owns the real card layers. These stand-ins carry the same bounds,
        // anchor point and rim treatment, and sit inside a track layer exactly
        // as U1's will, so the presenter is exercised through the same
        // coordinate conversion it will use in the shipped build.
        track = CALayer()
        track.name = "carousel.track.standin"
        track.frame = host.layer?.bounds ?? .zero
        host.layer?.addSublayer(track)

        cardLayers = (0..<6).map { index in
            let layer = CALayer()
            layer.name = "carousel.card.standin.\(index)"
            layer.bounds = CGRect(origin: .zero, size: geometry.centreCardRect.size)
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.cornerRadius = geometry.cardCornerRadius
            layer.backgroundColor = NSColor(srgbRed: 0.16, green: 0.20, blue: 0.27, alpha: 1).cgColor
            // CONTRACT row 29's treatment: a light hairline rim, no shadow.
            // This is the control row 80 measures the selection ring against.
            layer.borderWidth = 1
            layer.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
            track.addSublayer(layer)
            return layer
        }

        presenter = CarouselGridPresenter(geometry: geometry, host: host)
        presenter.setCards(makeCards())
        applyCarouselRects()
    }

    override func tearDown() async throws {
        recorder.stop()
        CarouselOverlayMotion.resetAccessibilityProviders()
        window?.orderOut(nil)
        window = nil
        try await super.tearDown()
    }

    // MARK: - Fixture

    /// Carousel rest rects: the centred card at row 20's size, flanks at row
    /// 23's 0.94 with row 25's pitch, so the presenter starts from realistic
    /// non-uniform scales rather than from six identical rects.
    private func makeCards() -> [CarouselGridPresenter.Card] {
        let card = geometry.centreCardRect
        let pitch = geometry.viewport.width * 0.739
        return (0..<6).map { index in
            let offset = CGFloat(index - 2) * pitch
            let scale: CGFloat = index == 2 ? 1.0 : 0.94
            let width = card.width * scale
            let height = card.height * scale
            let rect = CGRect(
                x: card.midX + offset - width / 2,
                y: card.midY - height / 2,
                width: width,
                height: height
            )
            return CarouselGridPresenter.Card(layer: cardLayers[index], carouselRect: rect)
        }
    }

    private func applyCarouselRects() {
        presenter.setMode(.carousel, animated: false)
        presenter.setSelectedSlot(2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, card) in makeCards().enumerated() {
            let rect = card.carouselRect
            let scale = rect.width / cardLayers[index].bounds.width
            let centre = host.viewportToLayer(CGPoint(x: rect.midX, y: rect.midY))
            cardLayers[index].position = centre
            cardLayers[index].transform = CATransform3DMakeScale(scale, scale, 1)
        }
        CATransaction.commit()
    }

    private func probeAllCards() -> [String: CGFloat] {
        var values: [String: CGFloat] = [:]
        for (index, layer) in cardLayers.enumerated() {
            let presentation = layer.presentation()
            let position = presentation?.position ?? layer.position
            let transform = presentation?.transform ?? layer.transform
            values["card\(index).x"] = position.x
            values["card\(index).y"] = position.y
            values["card\(index).scale"] = transform.m11
            values["card\(index).opacity"] = CGFloat(presentation?.opacity ?? layer.opacity)
        }
        return values
    }

    private func spin(_ seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.004))
            await Task.yield()
        }
    }

    // MARK: - Row 77 (X1)

    func testGridToggleIsASharedElementTransitionNotAHardCut() async throws {
        recorder.start(in: host) { [weak self] in self?.probeAllCards() ?? [:] }
        presenter.toggle()
        await spin(CarouselOverlayMotion.gridTransition + 0.20)
        recorder.stop()

        XCTAssertGreaterThan(recorder.frameCount, 4,
                             "no frames were sampled at all — the instrument, not the build, failed")

        for index in 0..<6 {
            let xKey = "card\(index).x"
            let scaleKey = "card\(index).scale"
            print("[row 77] \(recorder.summary(xKey))")
            print("[row 77] \(recorder.summary(scaleKey))")

            XCTAssertGreaterThanOrEqual(recorder.movingFrameCount(xKey, epsilon: 0.05), 12,
                                        "row 77: card \(index) must interpolate over at least 12 frames")
            XCTAssertGreaterThanOrEqual(recorder.movingFrameCount(scaleKey, epsilon: 0.0005), 12,
                                        "row 77: card \(index) scale must interpolate over at least 12 frames")
            // A single-frame diff spike fails. A hard cut puts the whole travel
            // into one step, which is a fraction of 1.0.
            XCTAssertLessThan(recorder.largestStepFraction(xKey), 0.30,
                              "row 77: card \(index) shows a single-frame jump")
        }

        // And it landed where row 38 says it should.
        let layout = CarouselGridLayout(geometry: geometry)
        for index in 0..<6 {
            let expected = layout.rect(forSlot: index)
            let centre = host.viewportToLayer(CGPoint(x: expected.midX, y: expected.midY))
            XCTAssertEqual(cardLayers[index].position.x, centre.x, accuracy: 0.5)
            XCTAssertEqual(cardLayers[index].position.y, centre.y, accuracy: 0.5)
            XCTAssertEqual(cardLayers[index].transform.m11,
                           expected.width / cardLayers[index].bounds.width, accuracy: 0.001)
        }
    }

    func testRapidToggleRetargetsFromThePresentationValueInsteadOfJumping() async throws {
        recorder.start(in: host) { [weak self] in self?.probeAllCards() ?? [:] }
        presenter.toggle()
        await spin(0.10)
        presenter.toggle()
        await spin(CarouselOverlayMotion.gridTransition + 0.20)
        recorder.stop()

        XCTAssertGreaterThan(recorder.frameCount, 8, "instrument produced no frames")
        for index in 0..<6 {
            let key = "card\(index).x"
            let steps = recorder.deltas(key).map { abs($0) }.sorted()
            guard steps.count > 6 else { continue }
            let median = steps[steps.count / 2]
            let largest = steps.last ?? 0
            print("[row 77 reversal] card \(index) medianStep=\(median) largestStep=\(largest)")
            // A reversal that restarted from the target rather than from the
            // presentation value shows one step an order of magnitude past the
            // rest. Six times the median is a generous bound that still catches it.
            XCTAssertLessThan(largest, max(median * 6, 4),
                              "row 77: card \(index) jumped on reversal")
        }
        XCTAssertEqual(presenter.mode, .carousel)
    }

    // MARK: - Row 112, grid-toggle half (supporting evidence, H4 is the proof)

    func testGridToggleFrameIntervalsAreReported() async throws {
        recorder.start(in: host) { [weak self] in self?.probeAllCards() ?? [:] }
        presenter.toggle()
        await spin(CarouselOverlayMotion.gridTransition + 0.10)
        presenter.toggle()
        await spin(CarouselOverlayMotion.gridTransition + 0.10)
        recorder.stop()

        let intervals = recorder.intervals.sorted()
        XCTAssertGreaterThanOrEqual(intervals.count, 12, "instrument produced too few frames to report")
        let median = intervals[intervals.count / 2]
        let p95 = intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))]
        let maximum = intervals.last ?? 0
        let overBudget = intervals.filter { $0 > median * 1.5 }.count
        print("""
        [row 112 grid toggle, Debug configuration, in-process CADisplayLink]
        frames=\(recorder.frameCount) \
        median=\(String(format: "%.3f", median * 1000))ms \
        p95=\(String(format: "%.3f", p95 * 1000))ms \
        max=\(String(format: "%.3f", maximum * 1000))ms \
        dropped(>1.5x median)=\(overBudget)/\(intervals.count)
        """)
        // Gated only on the thing a Debug build can honestly promise: no hitch
        // past 100 ms. The 1 % over-budget figure in row 112 is measured on the
        // row-128 Release configuration under Instruments and is U7a's.
        XCTAssertLessThan(maximum, 0.100, "row 112: no hitch may exceed 100 ms")
    }

    // MARK: - Row 80 (X4)

    func testGridHasASelectionIndicatorTheSourceLacks() async throws {
        presenter.setMode(.grid, animated: false)
        presenter.setSelectedSlot(0)
        await spin(0.10)

        let image = try renderHost()
        let layout = CarouselGridLayout(geometry: geometry)
        let byOrientation = [false, true].map { flipped in
            (0..<6).map { slot in
                borderLuminance(in: image, around: layout.rect(forSlot: slot), flipY: flipped)
            }
        }

        // The bitmap's y orientation is resolved by measurement, not assumed:
        // exactly one of the two readings may show the ring, and if neither
        // does the test fails rather than silently picking the flattering one.
        let satisfying = byOrientation.filter { luminances in
            guard let selected = luminances.first else { return false }
            return luminances.dropFirst().allSatisfy { selected - $0 >= 20 }
        }
        for (index, luminances) in byOrientation.enumerated() {
            print("[row 80] orientation \(index == 0 ? "top-left" : "bottom-left"): \(luminances.map { String(format: "%.1f", $0) })")
        }
        XCTAssertEqual(satisfying.count, 1,
                       "row 80: exactly one orientation may show the ring; \(satisfying.count) did")

        // Second half of row 80: the indicator follows navigation.
        presenter.moveSelection(by: 1)
        await spin(CarouselOverlayMotion.selectionMove + 0.15)
        XCTAssertEqual(presenter.selectedSlot, 1)
        let expected = presenter.selectionIndicator.ringFrame(
            around: layout.rect(forSlot: 1), geometry: geometry
        )
        let inLayer = host.viewportToLayer(expected)
        XCTAssertEqual(presenter.selectionIndicator.layer.position.x, inLayer.midX, accuracy: 0.5)
        XCTAssertEqual(presenter.selectionIndicator.layer.position.y, inLayer.midY, accuracy: 0.5)

        // The grid is two-dimensional, so row 80's "follows navigation" has to
        // cover a row move as well as a column one, or the bottom row is
        // reachable only by walking through it.
        presenter.setSelectedSlot(0)
        presenter.moveSelectionByRow(1)
        XCTAssertEqual(presenter.selectedSlot, 3, "a row move lands in the same column, one row down")
        presenter.moveSelectionByRow(-1)
        XCTAssertEqual(presenter.selectedSlot, 0)

        // And it wraps with the carousel rather than clamping (row 51's rule).
        presenter.setSelectedSlot(5)
        presenter.moveSelection(by: 1)
        XCTAssertEqual(presenter.selectedSlot, 0, "row 80 selection wraps like row 51's carousel")
    }

    func testLeavingGridCommitsTheSelectedSlot() async throws {
        var committed: Int?
        presenter.onSelectionCommitted = { committed = $0 }
        presenter.setMode(.grid, animated: false)
        presenter.setSelectedSlot(4)
        presenter.setMode(.carousel, animated: false)
        XCTAssertEqual(committed, 4,
                       "the grid is selectable, which VIDEO-REVIEW 2.7 proves the source is without showing how")
    }

    // MARK: - Row 83 (X7)

    func testNoOverlayResidueSurvivesAClosedGrid() async throws {
        let before = try renderHost()

        presenter.toggle()
        await spin(CarouselOverlayMotion.gridTransition + 0.15)
        presenter.toggle()
        await spin(CarouselOverlayMotion.gridTransition + 1.0)

        XCTAssertEqual(presenter.residualOverlayLayerCount, 0,
                       "row 83: the selection ring is removed from the tree, not hidden")
        XCTAssertNil(presenter.selectionIndicator.layer.superlayer)
        for layer in cardLayers {
            XCTAssertNil(layer.animation(forKey: "carousel.grid.position"))
            XCTAssertNil(layer.animation(forKey: "carousel.grid.transform"))
            XCTAssertNil(layer.animation(forKey: "carousel.grid.fade"))
        }

        let after = try renderHost()
        let diff = meanAbsoluteDifference(before, after)
        print("[row 83] region diff one second after close: \(String(format: "%.3f", diff))")
        XCTAssertLessThan(diff, 1.0,
                          "row 83: the frame after close matches the frame before open")
    }

    // MARK: - Row 113 (S6), grid half

    func testReducedMotionCrossFadesWithNoVisibleTranslationOrScaleChange() async throws {
        CarouselOverlayMotion.reduceMotionProvider = { true }
        recorder.start(in: host) { [weak self] in self?.probeAllCards() ?? [:] }
        presenter.toggle()
        await spin(CarouselOverlayMotion.reducedCrossFade + 0.30)
        recorder.stop()

        XCTAssertGreaterThan(recorder.frameCount, 4, "instrument produced no frames")

        // The honest form of "zero translation and zero scale change": nothing
        // moves in any frame in which it can be seen. Geometry only ever
        // changes while opacity is at zero.
        for index in 0..<6 {
            let samples = recorder.samples
            var violations = 0
            for i in 1..<samples.count {
                let previous = samples[i - 1].values
                let current = samples[i].values
                let visible = (current["card\(index).opacity"] ?? 0) > 0.02
                    && (previous["card\(index).opacity"] ?? 0) > 0.02
                guard visible else { continue }
                let dx = abs((current["card\(index).x"] ?? 0) - (previous["card\(index).x"] ?? 0))
                let dScale = abs((current["card\(index).scale"] ?? 0) - (previous["card\(index).scale"] ?? 0))
                if dx > 0.5 || dScale > 0.002 { violations += 1 }
            }
            XCTAssertEqual(violations, 0,
                           "row 113: card \(index) moved or scaled in \(violations) visible frames")
            XCTAssertGreaterThan(recorder.movingFrameCount("card\(index).opacity", epsilon: 0.005), 4,
                                 "row 113: opacity must interpolate")
        }
        XCTAssertEqual(presenter.mode, .grid)
    }

    // MARK: - Row 80/113 (S6b), ring under reduced motion

    func testReducedMotionRingMovesOnlyWhileInvisible() async throws {
        // Ruling (d) A1: the previous shape committed geometry at full
        // opacity first and only then blinked — a teleport the row-113 letter
        // cannot see. Geometry must still be at A immediately after the move
        // and reach B only after the fade completes.
        CarouselOverlayMotion.reduceMotionProvider = { true }
        let indicator = presenter.selectionIndicator
        let frameA = CGRect(x: 100, y: 100, width: 200, height: 150)
        let frameB = CGRect(x: 400, y: 300, width: 200, height: 150)
        indicator.move(to: frameA, animated: false)
        indicator.move(to: frameB, animated: true)
        XCTAssertEqual(indicator.layer.position.x, frameA.midX, accuracy: 0.5)
        XCTAssertEqual(indicator.layer.position.y, frameA.midY, accuracy: 0.5)
        await spin(CarouselOverlayMotion.reducedCrossFade + 0.3)
        XCTAssertEqual(indicator.layer.position.x, frameB.midX, accuracy: 0.5)
        XCTAssertEqual(indicator.layer.position.y, frameB.midY, accuracy: 0.5)
    }

    // MARK: - Pixel helpers

    /// Renders the host's layer tree into a bitmap.
    ///
    /// `CALayer.render(in:)` is used rather than the ScreenCaptureKit path the
    /// H1 harness uses, and rather than `cacheDisplay`, for one reason: nothing
    /// in this fixture is a Metal-backed terminal surface. The Phase 0 spike
    /// proved `cacheDisplay` returns a 96 %-transparent image for a live
    /// ghostty view, so the guard below asserts real opaque content came back —
    /// a render that quietly produced nothing would make row 80 pass on an
    /// empty image.
    private func renderHost() throws -> NSBitmapImageRep {
        guard let layer = host.layer else { throw XCTSkip("host has no backing layer") }
        let scale: CGFloat = 2
        let pixelWidth = Int(Self.viewport.width * scale)
        let pixelHeight = Int(Self.viewport.height * scale)
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw XCTSkip("could not create a bitmap context") }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { throw XCTSkip("render produced no image") }
        let rep = NSBitmapImageRep(cgImage: image)

        let opaqueFraction = opaquePixelFraction(rep)
        // 0.25, not a half: in grid mode six cards at 0.277 W cover about 45 %
        // of the viewport and the rest is legitimately transparent. The guard
        // exists to catch the Phase 0 spike signature, a 96 %-transparent
        // image, not to assert coverage.
        XCTAssertGreaterThan(opaqueFraction, 0.25,
                             "the render came back \(Int((1 - opaqueFraction) * 100)) % transparent — measuring it would prove nothing")
        return rep
    }

    private func opaquePixelFraction(_ rep: NSBitmapImageRep) -> CGFloat {
        var opaque = 0
        var total = 0
        let step = 8
        for y in stride(from: 0, to: rep.pixelsHigh, by: step) {
            for x in stride(from: 0, to: rep.pixelsWide, by: step) {
                total += 1
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.9 { opaque += 1 }
            }
        }
        return total == 0 ? 0 : CGFloat(opaque) / CGFloat(total)
    }

    /// Mean luminance of the annulus that holds both a card's own hairline rim
    /// and the selection ring outside it — the band VIDEO-REVIEW 1.7 measured
    /// per grid card in the source.
    private func borderLuminance(in rep: NSBitmapImageRep, around cardRect: CGRect, flipY: Bool) -> CGFloat {
        let scale: CGFloat = 2
        let outer = cardRect.insetBy(dx: -5, dy: -5)
        let inner = cardRect.insetBy(dx: 2, dy: 2)
        var sum: CGFloat = 0
        var count = 0
        var y = outer.minY
        while y < outer.maxY {
            var x = outer.minX
            while x < outer.maxX {
                defer { x += 1 }
                if inner.contains(CGPoint(x: x, y: y)) { continue }
                let py = flipY ? (Self.viewport.height - y) : y
                let px = Int(x * scale)
                let pyi = Int(py * scale)
                guard px >= 0, pyi >= 0, px < rep.pixelsWide, pyi < rep.pixelsHigh,
                      let colour = rep.colorAt(x: px, y: pyi)?.usingColorSpace(.sRGB) else { continue }
                sum += (0.2126 * colour.redComponent
                        + 0.7152 * colour.greenComponent
                        + 0.0722 * colour.blueComponent) * 255
                count += 1
            }
            y += 1
        }
        return count == 0 ? 0 : sum / CGFloat(count)
    }

    private func meanAbsoluteDifference(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> CGFloat {
        var sum: CGFloat = 0
        var count = 0
        let step = 4
        for y in stride(from: 0, to: min(a.pixelsHigh, b.pixelsHigh), by: step) {
            for x in stride(from: 0, to: min(a.pixelsWide, b.pixelsWide), by: step) {
                guard let ca = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      let cb = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                sum += abs(ca.redComponent - cb.redComponent) * 255
                sum += abs(ca.greenComponent - cb.greenComponent) * 255
                sum += abs(ca.blueComponent - cb.blueComponent) * 255
                count += 3
            }
        }
        return count == 0 ? 0 : sum / CGFloat(count)
    }
}
