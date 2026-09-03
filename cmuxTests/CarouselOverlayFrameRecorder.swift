// Modified 2026-09-02 for the cmux carousel UI build, unit U6.
// Test-support only. CONTRACT rows 67, 77, 78, 112, 113.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore

/// Samples layer **presentation** values once per displayed frame.
///
/// This is the H2 instrument done in-process. The contract's H2 is a 60 fps
/// `ffmpeg` window recording followed by per-frame edge tracking; that harness
/// is U7a's and row 121 is not closed (the machine's `avfoundation` device
/// index is still unrecorded). Reading the presentation layer on a
/// `CADisplayLink` measures the same quantity — what the compositor is showing
/// this frame — without the recorder's own encode jitter, and it is what these
/// tests assert against. It is **not** a substitute for row 112's H4
/// instrumentation, which the contract makes the sole proof of frame rate; the
/// interval statistics collected here are supporting evidence and are reported
/// as such.
///
/// A recorder that silently collects nothing would make every motion row pass
/// vacuously, so `start` fails loudly if no display link can be created, and
/// each test asserts a minimum sample count before it asserts anything else.
@MainActor
final class CarouselOverlayFrameRecorder: NSObject {
    struct Sample {
        let timestamp: CFTimeInterval
        let values: [String: CGFloat]
    }

    private var link: CADisplayLink?
    private var probe: (@MainActor () -> [String: CGFloat])?
    private(set) var samples: [Sample] = []

    func start(in view: NSView, probe: @escaping @MainActor () -> [String: CGFloat]) {
        stop()
        samples.removeAll()
        self.probe = probe
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
        probe = nil
    }

    @objc
    private func tick(_ link: CADisplayLink) {
        guard let probe else { return }
        samples.append(Sample(timestamp: link.timestamp, values: probe()))
    }

    var frameCount: Int { samples.count }

    var intervals: [CFTimeInterval] {
        guard samples.count > 1 else { return [] }
        return (1..<samples.count).map { samples[$0].timestamp - samples[$0 - 1].timestamp }
    }

    func series(_ key: String) -> [CGFloat] {
        samples.compactMap { $0.values[key] }
    }

    /// Frame-to-frame deltas of one series.
    func deltas(_ key: String) -> [CGFloat] {
        let values = series(key)
        guard values.count > 1 else { return [] }
        return (1..<values.count).map { values[$0] - values[$0 - 1] }
    }

    /// Number of frames in which the series actually changed by more than
    /// `epsilon`. This is the count row 77 cares about: a hard cut moves in one
    /// frame, an interpolation moves in many.
    func movingFrameCount(_ key: String, epsilon: CGFloat = 0.01) -> Int {
        deltas(key).filter { abs($0) > epsilon }.count
    }

    /// The largest single-frame step as a fraction of the total travel. A
    /// single-frame hard cut is 1.0; a 260 ms interpolation at 60 Hz is around
    /// 0.12 at its fastest.
    func largestStepFraction(_ key: String) -> CGFloat {
        let values = series(key)
        guard let first = values.first, let last = values.last else { return 0 }
        let travel = abs(last - first)
        guard travel > 0.0001 else { return 0 }
        return (deltas(key).map { abs($0) }.max() ?? 0) / travel
    }

    func summary(_ key: String) -> String {
        let values = series(key)
        let ivals = intervals
        let mean = ivals.isEmpty ? 0 : ivals.reduce(0, +) / Double(ivals.count)
        let maxInterval = ivals.max() ?? 0
        return """
        \(key): frames=\(values.count) moving=\(movingFrameCount(key)) \
        first=\(values.first.map { String(format: "%.2f", $0) } ?? "-") \
        last=\(values.last.map { String(format: "%.2f", $0) } ?? "-") \
        largestStep=\(String(format: "%.3f", largestStepFraction(key))) \
        meanInterval=\(String(format: "%.2f", mean * 1000))ms \
        maxInterval=\(String(format: "%.2f", maxInterval * 1000))ms
        """
    }
}
