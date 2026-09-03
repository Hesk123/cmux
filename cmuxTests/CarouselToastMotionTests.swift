// Added 2026-09-02 for the cmux carousel UI build, unit U6.
// CONTRACT rows 14 (second terminal-native addition), 45, 67, 68, 78, 83, 113.
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
final class CarouselToastMotionTests: XCTestCase {
    private var window: NSWindow!
    private var host: CarouselOverlayHostView!
    private var presenter: CarouselToastPresenter!
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
        presenter = CarouselToastPresenter(host: host, geometry: geometry)
    }

    override func tearDown() async throws {
        recorder.stop()
        CarouselOverlayMotion.resetAccessibilityProviders()
        window?.orderOut(nil)
        window = nil
        try await super.tearDown()
    }

    private func sample() -> CarouselToast {
        CarouselToast(
            title: "ecombrain · fix/webhook-replay",
            body: "  ✓ 41 passed, 0 failed in 12.8s",
            status: .idle,
            slot: 3
        )
    }

    private func probeToast() -> [String: CGFloat] {
        guard let layer = presenter.presentedView?.layer else { return [:] }
        let presentation = layer.presentation()
        let transform = presentation?.transform ?? layer.transform
        let position = presentation?.position ?? layer.position
        return [
            "tx": transform.m41,
            "y": position.y,
            "opacity": CGFloat(presentation?.opacity ?? layer.opacity)
        ]
    }

    private func spin(_ seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.004))
            await Task.yield()
        }
    }

    private func spinUntil(_ condition: @MainActor () -> Bool, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.004))
            await Task.yield()
        }
        return condition()
    }

    // MARK: - Row 67 (M16)

    func testToastEntersBySlidingFromOffScreenRightWithNoOvershoot() async throws {
        var settledAt: CFTimeInterval?
        presenter.onSettled = { _ in settledAt = CACurrentMediaTime() }

        recorder.start(in: host) { [weak self] in self?.probeToast() ?? [:] }
        let startedAt = CACurrentMediaTime()
        presenter.present(sample())
        _ = await spinUntil({ settledAt != nil }, timeout: 2.0)
        recorder.stop()

        let settled = try XCTUnwrap(settledAt)
        let duration = settled - startedAt
        print("[row 67] entrance duration \(String(format: "%.1f", duration * 1000)) ms")
        XCTAssertEqual(duration, CarouselOverlayMotion.toastIn, accuracy: 0.050,
                       "row 67: 330 ms +/- 50 ms")

        XCTAssertGreaterThan(recorder.frameCount, 8, "instrument produced no frames")
        let tx = recorder.series("tx")
        let ys = recorder.series("y")
        print("[row 67] \(recorder.summary("tx"))")

        // Starts fully off-screen right, ends flush at the slot.
        let expectedStart = geometry.viewport.width - (presenter.presentedView?.frame.minX ?? 0)
        XCTAssertEqual(try XCTUnwrap(tx.first), expectedStart, accuracy: expectedStart * 0.25,
                       "row 67: begins off-screen right")
        XCTAssertEqual(try XCTUnwrap(tx.last), 0, accuracy: 1.0, "row 67: settles at the slot")

        // y fixed within 2 px.
        let minY = try XCTUnwrap(ys.min())
        let maxY = try XCTUnwrap(ys.max())
        XCTAssertLessThan(maxY - minY, 2.0, "row 67: y stays constant")

        // No overshoot: the value never passes its target and returns.
        XCTAssertGreaterThanOrEqual(tx.min() ?? 0, -1.0, "row 67: no overshoot past the settle point")

        // Deltas monotonically decreasing in magnitude.
        let magnitudes = recorder.deltas("tx").map { abs($0) }.filter { $0 > 0.001 }
        var regressions = 0
        for i in 1..<max(magnitudes.count, 1) where magnitudes[i] > magnitudes[i - 1] + 0.5 {
            regressions += 1
        }
        print("[row 67] delta magnitudes: \(magnitudes.map { String(format: "%.1f", $0) })")
        XCTAssertEqual(regressions, 0, "row 67: step sizes must decrease monotonically")

        // Opacity ramps rather than snapping.
        XCTAssertGreaterThan(recorder.movingFrameCount("opacity", epsilon: 0.005), 4,
                             "row 67: opacity ramps")
    }

    // MARK: - Row 68 (M17)

    func testDwellIsThreePointSixSecondsAcrossThreeConsecutiveToasts() async throws {
        var measured: [CFTimeInterval] = []
        var settledAt: CFTimeInterval = 0
        var cycleDone = false

        presenter.onSettled = { _ in settledAt = CACurrentMediaTime() }
        presenter.onExitBegan = { _ in measured.append(CACurrentMediaTime() - settledAt) }
        presenter.onDismissed = { _ in cycleDone = true }

        for index in 0..<3 {
            cycleDone = false
            presenter.present(CarouselToast(
                title: "session \(index)",
                body: "line \(index)",
                status: .running
            ))
            let finished = await spinUntil({ cycleDone }, timeout: 8.0)
            XCTAssertTrue(finished, "toast \(index) never completed its cycle")
        }

        XCTAssertEqual(measured.count, 3)
        for (index, dwell) in measured.enumerated() {
            print("[row 68] toast \(index) dwell \(String(format: "%.3f", dwell)) s")
            XCTAssertEqual(dwell, CarouselOverlayMotion.toastDwell, accuracy: 0.5,
                           "row 68: 3.6 s +/- 0.5 s")
        }
    }

    func testDwellPausesWhileTheWindowIsNotVisible() async throws {
        // Sonner's fourth principle, and the reason row 68's budget is not
        // spent on a toast nobody can see. Invisible when it works, so it is
        // asserted rather than trusted.
        var settledAt: CFTimeInterval = 0
        var dwell: CFTimeInterval?
        presenter.onSettled = { _ in settledAt = CACurrentMediaTime() }
        presenter.onExitBegan = { _ in dwell = CACurrentMediaTime() - settledAt }

        presenter.present(sample())
        _ = await spinUntil({ settledAt > 0 }, timeout: 2.0)
        await spin(0.4)
        presenter.setWindowVisible(false)
        await spin(1.2)
        presenter.setWindowVisible(true)

        let finished = await spinUntil({ dwell != nil }, timeout: 8.0)
        XCTAssertTrue(finished)
        let measured = try XCTUnwrap(dwell)
        print("[row 68 pause] wall clock \(String(format: "%.3f", measured)) s for a 3.6 s dwell paused 1.2 s")
        XCTAssertEqual(measured, CarouselOverlayMotion.toastDwell + 1.2, accuracy: 0.5,
                       "the paused interval is not spent")
    }

    // MARK: - Row 78 (X2)

    func testToastExitIsAnimatedWhereTheSourceHardCuts() async throws {
        var settled = false
        var dismissed = false
        presenter.onSettled = { _ in settled = true }
        presenter.onDismissed = { _ in dismissed = true }

        presenter.present(sample())
        _ = await spinUntil({ settled }, timeout: 2.0)

        recorder.start(in: host) { [weak self] in self?.probeToast() ?? [:] }
        let exitStart = CACurrentMediaTime()
        presenter.dismiss()
        _ = await spinUntil({ dismissed }, timeout: 2.0)
        let exitDuration = CACurrentMediaTime() - exitStart
        recorder.stop()

        print("[row 78] \(recorder.summary("tx"))")
        print("[row 78] exit duration \(String(format: "%.1f", exitDuration * 1000)) ms")

        // VIDEO-REVIEW 2.9: the source disappears between two adjacent frames,
        // three times out of three. Row 78 requires at least eight.
        let movingTranslation = recorder.movingFrameCount("tx", epsilon: 0.5)
        let movingOpacity = recorder.movingFrameCount("opacity", epsilon: 0.005)
        XCTAssertGreaterThanOrEqual(max(movingTranslation, movingOpacity), 8,
                                    "row 78: the exit spans at least 8 frames")

        // Monotonic, and leaving by the path it arrived on rather than by a new
        // one, which is the spatial-consistency rule.
        let opacity = recorder.series("opacity")
        var opacityRegressions = 0
        for i in 1..<max(opacity.count, 1) where opacity[i] > opacity[i - 1] + 0.01 {
            opacityRegressions += 1
        }
        XCTAssertEqual(opacityRegressions, 0, "row 78: opacity falls monotonically")
        let tx = recorder.series("tx")
        if let first = tx.first, let last = tx.last {
            XCTAssertGreaterThan(last, first, "the exit travels right, the direction it entered from")
        }

        // Faster out than in.
        XCTAssertLessThan(CarouselOverlayMotion.toastOut, CarouselOverlayMotion.toastIn)
    }

    // MARK: - Row 83 (X7)

    func testNoToastResidueSurvivesDismissal() async throws {
        var dismissed = false
        presenter.onSettled = { [weak presenter] _ in presenter?.dismiss() }
        presenter.onDismissed = { _ in dismissed = true }
        presenter.present(sample())
        _ = await spinUntil({ dismissed }, timeout: 4.0)
        await spin(1.0)

        XCTAssertEqual(presenter.residualSubviewCount, 0,
                       "row 83: the toast view leaves the hierarchy, it is not left hidden")
        XCTAssertNil(presenter.presentedView)
        XCTAssertFalse(presenter.isPresenting)
        XCTAssertFalse(host.subviews.contains { $0 is CarouselToastView })
    }

    // MARK: - Replace

    func testASecondToastReplacesTheFirstInTheSameSlot() async throws {
        var settledTitles: [String] = []
        presenter.onSettled = { settledTitles.append($0.title) }

        presenter.present(CarouselToast(title: "first", body: "a", status: .running))
        _ = await spinUntil({ !settledTitles.isEmpty }, timeout: 2.0)
        presenter.present(CarouselToast(title: "second", body: "b", status: .idle))
        _ = await spinUntil({ settledTitles.count == 2 }, timeout: 4.0)

        XCTAssertEqual(settledTitles, ["first", "second"])
        XCTAssertEqual(presenter.currentToast?.title, "second")
        // One slot, one toast — never two stacked.
        XCTAssertEqual(host.subviews.filter { $0 is CarouselToastView }.count, 1)
        let replacement = try XCTUnwrap(presenter.presentedView)
        XCTAssertEqual(replacement.frame.maxX, Self.viewport.width - 16, accuracy: 0.5,
                       "the replacement keeps the same right edge (row 73)")
        XCTAssertEqual(replacement.frame.minY, 53, accuracy: 0.5,
                       "and the same top edge")
    }

    // MARK: - Row 113 (S6), toast half

    func testReducedMotionToastFadesWithoutTranslating() async throws {
        CarouselOverlayMotion.reduceMotionProvider = { true }
        var settled = false
        presenter.onSettled = { _ in settled = true }

        recorder.start(in: host) { [weak self] in self?.probeToast() ?? [:] }
        presenter.present(sample())
        _ = await spinUntil({ settled }, timeout: 2.0)
        recorder.stop()

        XCTAssertGreaterThan(recorder.frameCount, 4, "instrument produced no frames")
        let tx = recorder.series("tx")
        for value in tx {
            XCTAssertEqual(value, 0, accuracy: 0.001, "row 113: zero translation under reduced motion")
        }
        XCTAssertGreaterThan(recorder.movingFrameCount("opacity", epsilon: 0.005), 3,
                             "row 113: opacity interpolates instead")
    }

    // MARK: - Row 14, the second terminal-native addition

    func testToastCarriesTerminalOutputAndTheViewOwnsTheTruncation() async throws {
        let long = String(repeating: "npm warn deprecated inflight@1.0.6 ", count: 8)
        let toast = CarouselToast(title: "hive · main", body: long, status: .running)
        XCTAssertEqual(toast.body, long,
                       "the model keeps the whole line; eliding is the view's job, so a test can tell them apart")

        presenter.present(toast)
        let view = try XCTUnwrap(presenter.presentedView)
        await spin(0.4)

        let body = try XCTUnwrap(
            view.subviews.compactMap { $0 as? NSTextField }
                .first { $0.accessibilityIdentifier() == CarouselToastView.bodyAccessibilityIdentifier }
        )
        XCTAssertEqual(body.stringValue, long)
        XCTAssertEqual(body.lineBreakMode, .byTruncatingTail, "row 37: one line, ellipsised")
        XCTAssertEqual(body.maximumNumberOfLines, 1)
        // CONTRACT row 45: no monospace in the chrome, terminal text included.
        let family = try XCTUnwrap(body.font?.familyName)
        XCTAssertFalse(family.lowercased().contains("mono"), "row 45: chrome type is sans")
        XCTAssertFalse(family.lowercased().contains("menlo"), "row 45: chrome type is sans")
        XCTAssertLessThanOrEqual(body.frame.maxX, view.bounds.width - geometry.scaled(13),
                                 "the body stays inside the pill's right inset")
        XCTAssertEqual(view.frame.width, geometry.toastMaxWidth, accuracy: 1,
                       "a long line saturates the cap rather than overflowing it")

        // Defined empty state, per row 16's rubric.
        let empty = CarouselToast.emptyBody(for: "hive · main", status: .stopped)
        XCTAssertFalse(empty.body.isEmpty)
    }

    func testToastGeometryOnScreenMatchesRow37() async throws {
        presenter.present(sample())
        let view = try XCTUnwrap(presenter.presentedView)
        await spin(0.5)
        XCTAssertEqual(view.frame.maxX, Self.viewport.width - 16, accuracy: 1,
                       "row 37: right edge fixed")
        XCTAssertEqual(view.frame.minY, 53, accuracy: 1, "row 37: top edge fixed")
        XCTAssertEqual(view.frame.height, geometry.toastHeight, accuracy: 1, "row 37: height fixed")
        XCTAssertLessThanOrEqual(view.frame.width, geometry.toastMaxWidth + 0.5,
                                 "row 37: 0.225 W is the ceiling")
        XCTAssertGreaterThanOrEqual(view.frame.width, geometry.toastMinWidth - 0.5)
    }

    /// The correction itself: the width follows the content while the top and
    /// the right edge do not move. A fixed-width build passes every other toast
    /// assertion and fails this one.
    func testToastWidthFollowsItsContentWhileTheAnchorDoesNot() async throws {
        var widths: [CGFloat] = []
        var frames: [CGRect] = []

        for body in ["ok", String(repeating: "compiling target cmux ", count: 6)] {
            var settled = false
            presenter.onSettled = { _ in settled = true }
            presenter.present(CarouselToast(title: "hive", body: body, status: .running))
            _ = await spinUntil({ settled }, timeout: 4.0)
            let view = try XCTUnwrap(presenter.presentedView)
            widths.append(view.frame.width)
            frames.append(view.frame)
            presenter.dismiss()
            _ = await spinUntil({ !self.presenter.isPresenting }, timeout: 4.0)
        }

        print("[row 37 corrected] widths: \(widths.map { String(format: "%.1f", $0) })")
        XCTAssertEqual(widths.count, 2)
        XCTAssertGreaterThan(widths[1], widths[0] + 10,
                             "a longer line makes a wider pill")
        XCTAssertEqual(frames[0].maxX, frames[1].maxX, accuracy: 0.5,
                       "the right edge does not move between them")
        XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 0.5,
                       "nor does the top edge")
        XCTAssertEqual(frames[0].height, frames[1].height, accuracy: 0.5,
                       "nor does the height")
        XCTAssertLessThanOrEqual(widths[1], geometry.toastMaxWidth + 0.5, "still capped")
    }

    // MARK: - Row 37 corrected, mid-band + ruling (d)

    func testToastWidthTracksContentInsideTheClamps() async throws {
        // "ok" saturates the floor and the 6x line the ceiling, so a
        // constant-width build passes both. This body lands mid-band
        // (measured ~252 CSS on the reference panel): it fails on a constant
        // and on either clamp.
        var settled = false
        presenter.onSettled = { _ in settled = true }
        presenter.present(CarouselToast(title: "hive", body: "compiling target cmux xcodebuild", status: .running, slot: 0))
        _ = await spinUntil({ settled }, timeout: 4.0)
        let view = try XCTUnwrap(presenter.presentedView)
        XCTAssertGreaterThan(view.frame.width, geometry.toastMinWidth + 1)
        XCTAssertLessThan(view.frame.width, geometry.toastMaxWidth - 1)
        presenter.dismiss()
        _ = await spinUntil({ !self.presenter.isPresenting }, timeout: 4.0)
    }

    func testToastAccessibilityLabelNamesTheStatus() async throws {
        // Ruling (d) A3: VoiceOver must say whether the session is running,
        // not just read the title and body the dot's colour already codes.
        var settled = false
        presenter.onSettled = { _ in settled = true }
        presenter.present(CarouselToast(title: "hive", body: "done", status: .stopped, slot: 0))
        _ = await spinUntil({ settled }, timeout: 4.0)
        let view = try XCTUnwrap(presenter.presentedView)
        XCTAssertTrue(view.accessibilityLabel().contains("Status: stopped"))
        presenter.dismiss()
        _ = await spinUntil({ !self.presenter.isPresenting }, timeout: 4.0)
    }

    func testStatusShapeVariesWithoutColour() async throws {
        // Ruling (d) A2: with differentiate-without-colour on, idle renders
        // as a ring rather than a filled dot; with it off, today's pixels.
        CarouselOverlayMotion.differentiateWithoutColorProvider = { true }
        var settled = false
        presenter.onSettled = { _ in settled = true }
        presenter.present(CarouselToast(title: "hive", body: "waiting", status: .idle, slot: 0))
        _ = await spinUntil({ settled }, timeout: 4.0)
        let shaped = try XCTUnwrap(presenter.presentedView)
        XCTAssertGreaterThan(shaped.statusDot.borderWidth, 0, "idle renders as a ring, not a filled dot")
        presenter.dismiss()
        _ = await spinUntil({ !self.presenter.isPresenting }, timeout: 4.0)

        CarouselOverlayMotion.differentiateWithoutColorProvider = { false }
        settled = false
        presenter.present(CarouselToast(title: "hive", body: "waiting", status: .idle, slot: 0))
        _ = await spinUntil({ settled }, timeout: 4.0)
        let plain = try XCTUnwrap(presenter.presentedView)
        XCTAssertEqual(plain.statusDot.borderWidth, 0, "default pixels keep today's plain dot")
        presenter.dismiss()
        _ = await spinUntil({ !self.presenter.isPresenting }, timeout: 4.0)
    }
}
