// Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT rows 119, 121).
//
// Clock alignment for H2. A screen recording and the process driving the UI keep
// two unrelated clocks, so a duration measured from recorded frames cannot be
// compared to a timestamp taken in the app unless something visible ties them
// together. This program is that something: it paints the whole screen white for a
// known number of frames, prints the exact host time of the first white frame, and
// then gets out of the way.
//
// CONTRACT row 119 requires the marker to be a screen flash and NOT the keycap
// hint. The keycap is an animation under test; using it to align the clock would
// make row 62 assert its own input.
//
// It also serves row 121's "known-moving target": after the flash it sweeps a bar
// across the screen at a fixed points-per-second, so a capture can be checked for
// motion rather than only for frame count. A static screen yields the right frame
// count too, so a count alone proves nothing about whether motion was recorded.
//
// Build:  swiftc -O -o marker-flash MarkerFlash.swift
// Run:    ./marker-flash --flash-frames 3 --sweep-seconds 2.0
// Output (stdout, one JSON object): {"flash_host_time":..., "flash_wall_clock":..., ...}

import AppKit
import QuartzCore

@MainActor
final class MarkerView: NSView {
    var phase: Phase = .idle
    var sweepFraction: Double = 0

    enum Phase {
        case idle
        case flash
        case sweep
        case done
    }

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        switch phase {
        case .flash:
            NSColor.white.setFill()
            bounds.fill()
        case .sweep:
            NSColor.black.setFill()
            bounds.fill()
            NSColor.white.setFill()
            let barWidth = bounds.width * 0.05
            let x = (bounds.width - barWidth) * CGFloat(sweepFraction)
            NSRect(x: x, y: 0, width: barWidth, height: bounds.height).fill()
        case .idle, .done:
            NSColor.black.setFill()
            bounds.fill()
        }
    }
}

@MainActor
final class MarkerController: NSObject, NSApplicationDelegate {
    private let flashFrames: Int
    private let sweepSeconds: Double
    private let window: NSWindow
    private let view: MarkerView

    private var displayLink: CADisplayLink?
    private var framesSeen = 0
    private var flashHostTime: Double?
    private var flashWallClock: Double?
    private var sweepStart: Double?
    private var frameTimestamps: [Double] = []

    init(flashFrames: Int, sweepSeconds: Double, screen: NSScreen) {
        self.flashFrames = max(1, flashFrames)
        self.sweepSeconds = max(0, sweepSeconds)
        self.view = MarkerView(frame: screen.frame)
        self.window = NSWindow(contentRect: screen.frame,
                               styleMask: .borderless,
                               backing: .buffered,
                               defer: false,
                               screen: screen)
        super.init()
        window.contentView = view
        window.level = .screenSaver
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.backgroundColor = .black
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenNone]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.orderFrontRegardless()
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        view.phase = .flash
        view.needsDisplay = true
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        frameTimestamps.append(now)

        switch view.phase {
        case .flash:
            if flashHostTime == nil {
                flashHostTime = now
                flashWallClock = Date.now.timeIntervalSince1970
            }
            framesSeen += 1
            if framesSeen >= flashFrames {
                if sweepSeconds > 0 {
                    view.phase = .sweep
                    sweepStart = now
                } else {
                    finish(link)
                    return
                }
            }
            view.needsDisplay = true
        case .sweep:
            guard let start = sweepStart else {
                finish(link)
                return
            }
            let elapsed = now - start
            view.sweepFraction = min(1.0, elapsed / sweepSeconds)
            view.needsDisplay = true
            if elapsed >= sweepSeconds {
                finish(link)
                return
            }
        case .idle, .done:
            break
        }
    }

    private func finish(_ link: CADisplayLink) {
        view.phase = .done
        link.invalidate()
        displayLink = nil
        window.orderOut(nil)
        emitReport()
        NSApplication.shared.terminate(nil)
    }

    private func emitReport() {
        var deltas: [Double] = []
        if frameTimestamps.count > 1 {
            for i in 1..<frameTimestamps.count {
                deltas.append(frameTimestamps[i] - frameTimestamps[i - 1])
            }
        }
        let mean = deltas.isEmpty ? 0 : deltas.reduce(0, +) / Double(deltas.count)
        let report: [String: Any] = [
            "flash_host_time": flashHostTime ?? 0,
            "flash_wall_clock": flashWallClock ?? 0,
            "flash_frames": flashFrames,
            "sweep_seconds": sweepSeconds,
            "frames_driven": frameTimestamps.count,
            "mean_frame_interval": mean,
            "implied_fps": mean > 0 ? 1.0 / mean : 0,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            FileHandle.standardError.write(Data("marker: could not serialize report\n".utf8))
            return
        }
        print(text)
    }
}

@MainActor
func parseArguments() -> (flashFrames: Int, sweepSeconds: Double) {
    var flashFrames = 3
    var sweepSeconds = 2.0
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--flash-frames":
            if let v = it.next(), let n = Int(v) { flashFrames = n }
        case "--sweep-seconds":
            if let v = it.next(), let d = Double(v) { sweepSeconds = d }
        default:
            break
        }
    }
    return (flashFrames, sweepSeconds)
}

@main
struct MarkerFlashMain {
    // Top-level code in a Swift script is nonisolated, so calling a @MainActor entry
    // point from it is an actor-isolation error. @main with a @MainActor main() is the
    // supported way to say "this program starts on the main actor" without reaching for
    // MainActor.assumeIsolated, which would be asserting a guarantee rather than stating one.
    @MainActor
    static func main() {
        guard let screen = NSScreen.main else {
            FileHandle.standardError.write(Data("marker: no main screen\n".utf8))
            exit(2)
        }
        let args = parseArguments()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = MarkerController(flashFrames: args.flashFrames,
                                          sweepSeconds: args.sweepSeconds,
                                          screen: screen)
        app.delegate = controller
        app.run()
    }
}
