#if DEBUG
import AppKit
import QuartzCore

/// U2's on-device motion instrument.
///
/// Drives the real `CarouselTrackAnimator`, `CarouselChipRoll`,
/// `CarouselKeycapHint`, `CarouselSendFeedback` and `CarouselWorkingIndicator`
/// against a stand-in card track, and records every animated property's
/// **presentation** value on every `CADisplayLink` callback.
///
/// This is deliberately not a screen recording. H2's ffmpeg pass measures what
/// a camera would see and is run separately; this measures what the compositor
/// was actually asked to draw, at full 60 Hz, with no pixel-tracking error —
/// which is the only way to read a value like row 54's 0.971 track factor to
/// three decimals, and the only way to answer row 55's "is every card sharing
/// one track value" without inverting it out of edge positions.
///
/// It reaches the socket through the existing `screenshot` verb, exactly as the
/// Phase 0 spike did, so it needs no change to the command policy and inherits
/// the correct off-main lane.
///
/// DEBUG only. Never compiled into a shipped build.
@MainActor
final class CarouselMotionProbe: NSObject {

    /// The socket worker returns as soon as the run completes, so the probe
    /// needs an owner for the duration.
    static var retained: CarouselMotionProbe?

    private static let cardCount = 5
    private static let dotCount = 3

    private let reduced: Bool
    private let outputDirectory: URL

    private let window: NSWindow
    private let viewport: CGRect
    private let pitch: CGFloat

    private let trackLayers: CarouselTrackAnimator.Layers
    private let animator: CarouselTrackAnimator
    private var cards: [CALayer] = []

    private let chipPill = CALayer()
    private var chipRoll: CarouselChipRoll?
    private var chipLabels: [CALayer] = []

    private let keycapContainer = CALayer()
    private var keycap: CarouselKeycapHint?

    private let pressTarget = CALayer()
    private let voiceIcon = CALayer()
    private let sendIcon = CALayer()
    private var send: CarouselSendFeedback?

    private var dots: [CALayer] = []
    private var working: CarouselWorkingIndicator?

    private weak var hostLayer: CALayer?
    private var link: CADisplayLink?
    private var frameIndex = 0
    private var samples: [String] = []
    private var events: [String] = []
    private var startTime: CFTimeInterval = 0
    private var finish: ((String) -> Void)?

    /// Frame numbers at 60 Hz. Each phase gets a 90-frame (1.5 s) window so a
    /// keycap dwell plus fade fits inside its own phase.
    private enum Phase {
        /// Row 119's clock alignment. The whole window flashes white for
        /// exactly one frame, so an H2 screen recording can find frame zero by
        /// a luminance spike instead of by the keycap — which would make row
        /// 62's "visible within 1 frame of the event" assertion circular, since
        /// the keycap is the thing under test.
        static let markerOn = 18
        static let markerOff = 19
        static let single = 30
        static let retargetA = 120
        static let retargetB = 126        // 100 ms in — genuinely mid-flight
        static let reverseA = 210
        static let reverseB = 216
        static let burstStart = 300       // five presses, 4 frames apart
        static let pairA = 390
        static let pairB = 410            // 333 ms apart, row 56's stated case
        static let chipForward = 480
        static let chipBackward = 570
        static let dotsOn = 660
        static let total = 780
    }

    /// Row 119's four values, read from the live screen and carried into the
    /// report so the evidence artefact states them rather than the prose.
    struct Precondition {
        var lines: [String]
        var passed: Bool
    }

    private(set) var precondition = Precondition(lines: [], passed: false)

    init(reduced: Bool) {
        self.reduced = reduced
        outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-carousel-u2")
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        // CONTRACT row 9 card, D-13 gap, D-2 side scale -> row 25's pitch. The
        // probe restates the arithmetic rather than the answer so a geometry
        // change in U1 cannot leave a stale 993.96 here.
        let card = CGSize(width: 968, height: 761)
        pitch = card.width / 2 + 55 + (card.width * CarouselMotion.flankScale) / 2

        let visible = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1344, height: 1080)
        let size = CGSize(width: min(1344, visible.width - 40), height: min(1080, visible.height - 40))
        viewport = CGRect(origin: .zero, size: size)

        let scale = NSScreen.main?.backingScaleFactor ?? 0
        let visible = NSScreen.main?.visibleFrame.size ?? .zero
        let scaleOK = scale == 2.0
        let visibleOK = visible.width >= 1344 && visible.height >= 1080
        let windowOK = size.width == 1344 && size.height == 1080
        precondition = Precondition(
            lines: [
                "backingScaleFactor=\(scale) required=2.0 \(scaleOK ? "OK" : "FAIL")",
                "visibleFrame=\(Int(visible.width))x\(Int(visible.height)) required>=1344x1080 \(visibleOK ? "OK" : "FAIL")",
                "window=\(Int(size.width))x\(Int(size.height)) required=1344x1080 \(windowOK ? "OK" : "FAIL")",
                "backingStore=\(Int(size.width * scale))x\(Int(size.height * scale)) expected=2688x2160",
            ],
            passed: scaleOK && visibleOK && windowOK
        )

        window = NSWindow(
            contentRect: NSRect(origin: CGPoint(x: 20, y: 20), size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "carousel motion probe"

        trackLayers = CarouselTrackAnimator.makeLayers(viewport: viewport)
        let gate = CarouselReduceMotion.fixed(reduced)
        animator = CarouselTrackAnimator(layers: trackLayers, pitch: pitch, reduceMotion: gate)

        super.init()

        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = host
        guard let hostLayer = host.layer else { return }
        self.hostLayer = hostLayer
        hostLayer.addSublayer(trackLayers.recoil)

        buildCards(cardSize: card)
        buildChip(gate: gate)
        buildKeycap(gate: gate)
        buildSendControl(hostLayer: hostLayer, gate: gate)
        buildDots(hostLayer: hostLayer, gate: gate)
    }

    // MARK: - Scene

    private func buildCards(cardSize: CGSize) {
        // Five slots so the row-54 solvability observable exists: with the
        // centre entering and its neighbour leaving, three cards are still
        // holding c = 0.94 in every mid-switch frame.
        let centreSlot = Self.cardCount / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for slot in 0..<Self.cardCount {
            let layer = CALayer()
            layer.bounds = CGRect(origin: .zero, size: cardSize)
            layer.position = CGPoint(
                x: viewport.midX + CGFloat(slot - centreSlot) * pitch,
                y: viewport.midY
            )
            layer.cornerRadius = 26
            layer.masksToBounds = true
            layer.backgroundColor = NSColor(
                calibratedHue: CGFloat(slot) / CGFloat(Self.cardCount),
                saturation: 0.35,
                brightness: 0.45,
                alpha: 1
            ).cgColor
            trackLayers.track.addSublayer(layer)
            let resting = slot == centreSlot ? CarouselMotion.centreScale : CarouselMotion.flankScale
            animator.register(card: layer, scale: resting)
            cards.append(layer)
        }
    }

    private func buildChip(gate: CarouselReduceMotion) {
        chipPill.bounds = CGRect(x: 0, y: 0, width: 120, height: 26)
        chipPill.anchorPoint = CGPoint(x: 0, y: 0.5)
        chipPill.position = CGPoint(x: 40, y: 40)
        chipPill.cornerRadius = 8
        chipPill.masksToBounds = true
        chipPill.backgroundColor = NSColor(red: 0.149, green: 0.180, blue: 0.216, alpha: 1).cgColor
        window.contentView?.layer?.addSublayer(chipPill)

        chipRoll = CarouselChipRoll(
            pill: chipPill,
            makeLabel: { [weak self] text in
                let label = CATextLayer()
                label.string = text
                label.fontSize = 13
                label.foregroundColor = NSColor.white.cgColor
                label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                label.bounds = CGRect(x: 0, y: 0, width: 200, height: 18)
                label.anchorPoint = CGPoint(x: 0, y: 0.5)
                label.position = CGPoint(x: 10, y: 13)
                self?.chipLabels.append(label)
                return label
            },
            reduceMotion: gate
        )
        chipRoll?.setInitial("Calendar", pillWidth: 120)
    }

    private func buildKeycap(gate: CarouselReduceMotion) {
        keycapContainer.bounds = CGRect(x: 0, y: 0, width: 300, height: 60)
        keycapContainer.position = CGPoint(x: viewport.midX, y: 110)
        window.contentView?.layer?.addSublayer(keycapContainer)
        keycap = CarouselKeycapHint(
            container: keycapContainer,
            windowWidth: viewport.width,
            makeCap: { glyph, size, radius in
                let cap = CATextLayer()
                cap.string = glyph
                cap.alignmentMode = .center
                cap.fontSize = size.height * 0.5
                cap.foregroundColor = NSColor.white.cgColor
                cap.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
                cap.cornerRadius = radius
                cap.masksToBounds = true
                cap.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
                return cap
            },
            reduceMotion: gate
        )
    }

    private func buildSendControl(hostLayer: CALayer, gate: CarouselReduceMotion) {
        pressTarget.bounds = CGRect(x: 0, y: 0, width: 35, height: 35)
        pressTarget.position = CGPoint(x: viewport.maxX - 60, y: 40)
        hostLayer.addSublayer(pressTarget)
        for icon in [voiceIcon, sendIcon] {
            icon.bounds = pressTarget.bounds
            icon.position = CGPoint(x: 17.5, y: 17.5)
            icon.backgroundColor = NSColor.systemBlue.cgColor
            icon.cornerRadius = 17.5
            pressTarget.addSublayer(icon)
        }
        send = CarouselSendFeedback(
            pressTarget: pressTarget,
            voiceIcon: voiceIcon,
            sendIcon: sendIcon,
            suggestionChips: [],
            reduceMotion: gate
        )
    }

    private func buildDots(hostLayer: CALayer, gate: CarouselReduceMotion) {
        for index in 0..<Self.dotCount {
            let dot = CALayer()
            dot.bounds = CGRect(x: 0, y: 0, width: 6, height: 6)
            dot.position = CGPoint(x: 200 + CGFloat(index) * 12, y: 40)
            dot.cornerRadius = 3
            dot.backgroundColor = NSColor.white.cgColor
            dot.opacity = 0
            hostLayer.addSublayer(dot)
            dots.append(dot)
        }
        working = CarouselWorkingIndicator(dots: dots, reduceMotion: gate)
    }

    // MARK: - Run

    func run(_ completion: @escaping (String) -> Void) {
        guard precondition.passed else {
            // Row 119: "aborts loudly if any fails", rather than letting the
            // absolute-value rows void by exemption.
            completion(
                "ERROR: row 119 precondition FAILED - refusing to measure.\n"
                + precondition.lines.joined(separator: "\n")
                + "\nSet the display first: displayplacer \"id:<built-in> res:1920x1243 scaling:on\""
            )
            return
        }
        finish = completion
        window.orderFrontRegardless()
        guard let host = window.contentView else {
            completion("ERROR: probe window has no content view")
            return
        }
        samples.append(Self.header)
        events.append("t_ms,event")
        startTime = CACurrentMediaTime()
        let displayLink = host.displayLink(target: self, selector: #selector(tick(_:)))
        displayLink.add(to: .main, forMode: .common)
        link = displayLink
    }

    private func note(_ event: String) {
        events.append("\(millis(CACurrentMediaTime())),\(event)")
    }

    private func millis(_ time: CFTimeInterval) -> String {
        String(format: "%.3f", (time - startTime) * 1000)
    }

    @objc private func tick(_ sender: CADisplayLink) {
        drive(frame: frameIndex)
        record(timestamp: sender.timestamp)
        frameIndex += 1

        guard frameIndex >= Phase.total else { return }
        sender.invalidate()
        link = nil
        window.orderOut(nil)
        let report = writeArtifacts()
        let completion = finish
        finish = nil
        completion?(report)
    }

    private func drive(frame: Int) {
        switch frame {
        case Phase.markerOn:
            setHostBackground(.white)
            note("marker.on")
        case Phase.markerOff:
            setHostBackground(.black)
            note("marker.off")
        case Phase.single:
            switchForward("single")
        case Phase.retargetA:
            switchForward("retarget.a")
        case Phase.retargetB:
            switchForward("retarget.b")
        case Phase.reverseA:
            switchForward("reverse.a")
        case Phase.reverseB:
            switchBackward("reverse.b")
        case Phase.burstStart, Phase.burstStart + 4, Phase.burstStart + 8,
             Phase.burstStart + 12, Phase.burstStart + 16:
            switchForward("burst")
        case Phase.pairA:
            switchForward("pair.a")
        case Phase.pairB:
            switchForward("pair.b")
        case Phase.chipForward:
            note("chip.forward")
            chipRoll?.roll(to: "Notion", pillWidth: 96, direction: .forward)
            keycap?.show(.next)
            note("keycap.show")
            send?.setMode(.send)
            note("send.mode")
            send?.flashPress()
            note("send.press")
        case Phase.chipBackward:
            note("chip.backward")
            chipRoll?.roll(to: "Lovable Workspace", pillWidth: 168, direction: .backward)
        case Phase.dotsOn:
            note("dots.on")
            working?.setRunning(true)
        default:
            break
        }
    }

    private func setHostBackground(_ color: NSColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostLayer?.backgroundColor = color.cgColor
        CATransaction.commit()
    }

    private func switchForward(_ label: String) { performSwitch(slots: 1, label: label) }
    private func switchBackward(_ label: String) { performSwitch(slots: -1, label: label) }

    /// Which card ramps is a function of where the centre is, so the probe
    /// tracks it the way U1's document view will.
    private var centreIndex = CarouselMotionProbe.cardCount / 2

    private func performSwitch(slots: Int, label: String) {
        note("switch.\(label).slots=\(slots)")
        let leaving = cards.indices.contains(centreIndex) ? cards[centreIndex] : nil
        // Wrap, so every phase has a real entering and leaving card and the
        // row-55 ramp evidence is not confined to the first switch. U1 owns
        // real wrap (row 57); this is the stand-in track's version of it.
        let nextIndex = ((centreIndex + slots) % Self.cardCount + Self.cardCount) % Self.cardCount
        let entering = cards.indices.contains(nextIndex) ? cards[nextIndex] : nil
        centreIndex = nextIndex
        animator.advance(
            by: slots,
            ramps: .init(entering: entering, leaving: leaving)
        ) { [weak self] in
            self?.note("settle.\(label)")
        }
    }

    // MARK: - Sampling

    private static var header: String {
        var columns = ["t_ms", "track_tx", "recoil_scale"]
        columns += (0..<cardCount).map { "card\($0)_scale" }
        columns += (0..<cardCount).map { "card\($0)_opacity" }
        columns += (0..<cardCount).map { "card\($0)_centre_x" }
        columns += ["chip_new_y", "chip_new_opacity", "chip_old_y", "chip_old_opacity", "pill_w"]
        columns += ["keycap_opacity", "press_scale", "voice_opacity", "send_opacity"]
        columns += (0..<dotCount).map { "dot\($0)_opacity" }
        return columns.joined(separator: ",")
    }

    private func record(timestamp: CFTimeInterval) {
        let recoil = number(trackLayers.recoil, "transform.scale") ?? 1
        let tx = number(trackLayers.track, "transform.translation.x") ?? 0

        var row: [String] = [millis(timestamp), fmt(tx), fmt(recoil)]
        let scales = cards.map { number($0, "transform.scale") ?? 1 }
        row += scales.map(fmt)
        row += cards.map { fmt(CGFloat($0.presentation()?.opacity ?? $0.opacity)) }
        // The rendered centre a frame-differ would track: the track's
        // translation carried through the recoil about the viewport centre. The
        // per-card scale is about the card's own centre and so cannot move it,
        // which is why rows 52, 55 and 56 all measure centres and not edges.
        row += cards.indices.map { slot in
            let rest = viewport.midX + CGFloat(slot - Self.cardCount / 2) * pitch
            return fmt(viewport.midX + (rest + tx - viewport.midX) * recoil)
        }

        let labels = chipLabels.suffix(2)
        let newLabel = labels.last
        let oldLabel = labels.count > 1 ? labels.first : nil
        row += [
            fmt(newLabel.flatMap { number($0, "transform.translation.y") } ?? 0),
            fmt(CGFloat(newLabel?.presentation()?.opacity ?? newLabel?.opacity ?? 0)),
            fmt(oldLabel.flatMap { number($0, "transform.translation.y") } ?? 0),
            fmt(CGFloat(oldLabel?.presentation()?.opacity ?? oldLabel?.opacity ?? 0)),
            fmt(number(chipPill, "bounds.size.width") ?? chipPill.bounds.width),
        ]
        row += [
            fmt(CGFloat(keycapContainer.presentation()?.opacity ?? keycapContainer.opacity)),
            fmt(number(pressTarget, "transform.scale") ?? 1),
            fmt(CGFloat(voiceIcon.presentation()?.opacity ?? voiceIcon.opacity)),
            fmt(CGFloat(sendIcon.presentation()?.opacity ?? sendIcon.opacity)),
        ]
        row += dots.map { fmt(CGFloat($0.presentation()?.opacity ?? $0.opacity)) }
        samples.append(row.joined(separator: ","))
    }

    private func number(_ layer: CALayer, _ keyPath: String) -> CGFloat? {
        guard let value = layer.presentation()?.value(forKeyPath: keyPath) as? NSNumber else {
            return nil
        }
        return CGFloat(value.doubleValue)
    }

    private func fmt(_ value: CGFloat) -> String { String(format: "%.6f", value) }

    private func writeArtifacts() -> String {
        let pass = reduced ? "reduced" : "normal"
        let framesURL = outputDirectory.appendingPathComponent("frames-\(pass).csv")
        let eventsURL = outputDirectory.appendingPathComponent("events-\(pass).csv")
        try? samples.joined(separator: "\n").write(to: framesURL, atomically: true, encoding: .utf8)
        try? events.joined(separator: "\n").write(to: eventsURL, atomically: true, encoding: .utf8)

        var out: [String] = []
        out.append("=== carousel motion probe (\(pass)) ===")
        // ROW 119 PRECONDITION, recorded in the artefact rather than asserted in
        // prose. The critic's point stands: a claim in a report is not a
        // recorded assertion, and at the panel's default mode this window
        // silently clamps to 1670x1033 and every number below it is wrong.
        out.append("--- row 119 precondition ---")
        out.append(precondition.lines.joined(separator: "\n"))
        out.append("row119=\(precondition.passed ? "PASS" : "FAIL")")
        out.append("--- measurement ---")
        out.append("frames=\(samples.count - 1) pitch=\(String(format: "%.2f", pitch))")
        out.append("frames_csv=\(framesURL.path)")
        out.append("events_csv=\(eventsURL.path)")
        out.append("=== end probe ===")
        return out.joined(separator: "\n")
    }
}
#endif
