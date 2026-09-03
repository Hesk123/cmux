import AppKit
import QuartzCore

/// The keycap hint: rows 36, 62 and 63.
///
/// Instant in on the frame of the chord, held while navigating, then an 83 ms
/// decelerating fade after the dwell. The asymmetry is the point — the source
/// measured no fade-in at all, and `emil-design-eng` bans animating a
/// keyboard-initiated action outright, because the hint appears on a keystroke
/// a user makes tens of times a session and any entrance reads as lag.
///
/// # Three caps, not two (row 36, D-12 and D-15)
///
/// The reference showed at most two caps because its chords were at most two
/// keys. Every navigation chord in this build is three (Ctrl-Cmd-Left,
/// Ctrl-Cmd-Right, Ctrl-Cmd-M, Ctrl-Cmd-K), because the two-key candidates were
/// all taken — Cmd-Shift-Left/Right by AppKit's own select-to-line-end, Ctrl-
/// Cmd-G by cmux's `.newWorkspaceGroup`. Three caps is therefore an
/// exceeds-source departure rather than a fidelity miss, and it is the honest
/// rendering of what the user actually pressed, which is what row 62 asserts.
@MainActor
final class CarouselKeycapHint {

    /// The keys actually pressed, in press order, as their glyphs.
    struct Chord: Equatable {
        var caps: [String]

        static let previous = Chord(caps: ["\u{2303}", "\u{2318}", "\u{2190}"])
        static let next = Chord(caps: ["\u{2303}", "\u{2318}", "\u{2192}"])
        static let grid = Chord(caps: ["\u{2303}", "\u{2318}", "M"])
        static let modeToggle = Chord(caps: ["\u{2303}", "\u{2318}", "K"])

        /// Spoken form of the chord for the accessibility floor (contract rows
        /// 108-113 annotation): a bare CALayer is invisible to VoiceOver, so
        /// U1's card publishes this string on its own accessibility element.
        var accessibilityValue: String {
            caps.map(Self.spokenCap).joined(separator: " ")
        }

        private static func spokenCap(_ cap: String) -> String {
            switch cap {
            case "\u{2303}": return "Control"
            case "\u{2318}": return "Command"
            case "\u{2190}": return "Left Arrow"
            case "\u{2192}": return "Right Arrow"
            default: return cap
            }
        }
    }

    /// Accessibility floor: the hint's label, published by U1's card element
    /// alongside `accessibilityValue` below.
    static let accessibilityLabel = "Carousel keyboard shortcuts"

    /// The shown chord's spoken form, if a chord is shown.
    var accessibilityValue: String? { shownChord?.accessibilityValue }

    private let container: CALayer
    private let makeCap: @MainActor (String, CGSize, CGFloat) -> CALayer
    private let reduceMotion: CarouselReduceMotion

    /// Window width W, for row 36's ratio-of-W geometry.
    private var windowWidth: CGFloat

    private var capLayers: [CALayer] = []
    private var shownChord: Chord?
    private var dwell: Task<Void, Never>?

    /// - Parameters:
    ///   - container: the layer the cap group is centred in. U1 places it in
    ///     the gap between the card bottom and the prompt bar (row 123).
    ///   - makeCap: builds one cap for a glyph, at a size and corner radius.
    init(
        container: CALayer,
        windowWidth: CGFloat,
        makeCap: @escaping @MainActor (String, CGSize, CGFloat) -> CALayer,
        reduceMotion: CarouselReduceMotion
    ) {
        self.container = container
        self.windowWidth = windowWidth
        self.makeCap = makeCap
        self.reduceMotion = reduceMotion
        container.opacity = 0
    }

    func setWindowWidth(_ width: CGFloat) {
        windowWidth = width
        if let shownChord { layout(shownChord) }
    }

    /// Row 62: visible on the same frame as the chord.
    ///
    /// Everything on this path is synchronous and every implicit action is
    /// disabled, so the hint is committed in the same transaction as the key
    /// event's run-loop turn. There is no `Task`, no timer and no animation
    /// between the keypress and the first visible frame.
    func show(_ chord: Chord) {
        dwell?.cancel()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if chord != shownChord {
            layout(chord)
            shownChord = chord
        }
        container.removeAnimation(forKey: "opacity")
        container.opacity = 1
        CATransaction.commit()

        dwell = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(CarouselMotion.keycapDwell * 1000)))
            guard !Task.isCancelled else { return }
            self?.fadeOut()
        }
    }

    /// Row 63: 83 ms, opacity monotonic and decelerating.
    ///
    /// Reduced motion keeps this unchanged. It is already an opacity-only
    /// transition with no translation and no scale, which is exactly what row
    /// 113 degrades everything else *to*.
    private func fadeOut() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = container.presentation()?.opacity ?? container.opacity
        fade.toValue = 0
        fade.duration = CarouselMotion.keycapFadeOut
        fade.timingFunction = CarouselMotion.switchCurve
        // Setting `opacity` outside a disabled transaction triggers Core
        // Animation's default action, which attaches its own 0.25 s animation
        // under the same "opacity" key and replaces this one. The probe
        // measured the fade at 233 ms against row 63's 83 +/- 25 before this.
        carouselCommit {
            container.add(fade, forKey: "opacity")
            container.opacity = 0
        }
    }

    func hideImmediately() {
        dwell?.cancel()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.removeAnimation(forKey: "opacity")
        container.opacity = 0
        CATransaction.commit()
    }

    /// Row 36: each cap `0.0298 W` x `0.0283 W`, radius `11/1344 W`, spaced
    /// `6.5/1344 W`, the group centred in `container`.
    private func layout(_ chord: Chord) {
        capLayers.forEach { $0.removeFromSuperlayer() }

        let size = CGSize(
            width: CarouselMotion.keycapWidthRatio * windowWidth,
            height: CarouselMotion.keycapHeightRatio * windowWidth
        )
        let spacing = CarouselMotion.keycapSpacingRatio * windowWidth
        let radius = CarouselMotion.keycapRadiusRatio * windowWidth
        let count = CGFloat(chord.caps.count)
        let groupWidth = count * size.width + max(0, count - 1) * spacing
        var x = container.bounds.midX - groupWidth / 2 + size.width / 2

        capLayers = chord.caps.map { glyph in
            let cap = makeCap(glyph, size, radius)
            cap.bounds = CGRect(origin: .zero, size: size)
            cap.position = CGPoint(x: x, y: container.bounds.midY)
            container.addSublayer(cap)
            x += size.width + spacing
            return cap
        }
    }
}
