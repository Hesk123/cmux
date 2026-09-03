// Added 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 37, 45, 70, 73, 123.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit

/// The toast pill. CONTRACT row 37: 0.225 W x 0.0521 W, top-right, ~16 CSS
/// right margin, top edge 24 CSS below the menu bar.
///
/// CONTRACT row 70 forbids a fourth token, so the fill is the prompt bar's
/// `#0B151D` and the radius is the prompt bar's 0.0164 W. CONTRACT row 45
/// forbids monospace in card chrome, and that holds here even though the body
/// text is terminal output: it is chrome *about* the terminal, and it is set in
/// the system sans at the same 12.5 CSS as every other subtitle.
///
/// **The width is content-dependent** and the pill is anchored top-right, per
/// the orchestrator's 2026-09-03 measurement: two source frames with the same
/// top and the same right edge measured 530.8 and 447.7 device wide. Row 37's
/// 0.225 W is therefore a ceiling, not a fixed width, and `preferredWidth(for:)`
/// measures the real strings.
///
/// The view's frame is always its settled rect. Motion is a layer transform, so
/// hit testing and accessibility read the true position at every moment and no
/// AppKit layout pass can fight the animation.
@MainActor
final class CarouselToastView: NSView {
    static let accessibilityIdentifierValue = "carousel.toast"
    static let titleAccessibilityIdentifier = "carousel.toast.title"
    static let bodyAccessibilityIdentifier = "carousel.toast.body"

    private let material = NSVisualEffectView()
    private let tint = NSView()
    private let tile = NSView()
    private let statusDot = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")

    private let geometry: CarouselOverlayGeometry

    /// Called when the pointer enters or leaves, so the presenter can hold the
    /// dwell open while someone is reading. Sonner's fourth principle: handle
    /// the edge case invisibly.
    var onHoverChanged: ((Bool) -> Void)?

    override var isFlipped: Bool { true }

    init(geometry: CarouselOverlayGeometry) {
        self.geometry = geometry
        super.init(frame: geometry.toastRect(width: geometry.toastMaxWidth))
        wantsLayer = true
        buildHierarchy()
        layOutContents()
        setAccessibilityIdentifier(Self.accessibilityIdentifierValue)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselToastView is created in code only")
    }

    // MARK: - Content

    /// The pill's natural width for this toast: insets, tile, gap, and whichever
    /// of the two strings is wider, clamped by the geometry's floor and ceiling.
    func preferredWidth(for toast: CarouselToast) -> CGFloat {
        let titleWidth = (toast.title as NSString)
            .size(withAttributes: [.font: Self.titleFont(geometry)]).width
        let bodyWidth = (toast.body as NSString)
            .size(withAttributes: [.font: Self.bodyFont(geometry)]).width
        let chrome = geometry.scaled(14) + geometry.scaled(26) + geometry.scaled(12) + geometry.scaled(14)
        let natural = chrome + ceil(max(titleWidth, bodyWidth))
        return min(max(natural, geometry.toastMinWidth), geometry.toastMaxWidth)
    }

    static func titleFont(_ geometry: CarouselOverlayGeometry) -> NSFont {
        .systemFont(ofSize: geometry.scaled(15), weight: .semibold)
    }

    static func bodyFont(_ geometry: CarouselOverlayGeometry) -> NSFont {
        .systemFont(ofSize: geometry.scaled(12.5))
    }

    func apply(_ toast: CarouselToast) {
        titleLabel.stringValue = toast.title
        bodyLabel.stringValue = toast.body
        statusDot.backgroundColor = Self.dotColor(for: toast.status).cgColor
        setAccessibilityLabel("\(toast.title). \(toast.body)")
    }

    private static func dotColor(for status: CarouselToast.Status) -> NSColor {
        switch status {
        case .running: return .systemGreen
        case .idle: return .systemBlue
        case .stopped: return .systemGray
        case .unknown: return .systemYellow
        }
    }

    // MARK: - Build

    private func buildHierarchy() {
        let radius = geometry.toastCornerRadius

        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = radius
        material.layer?.masksToBounds = true
        addSubview(material)

        tint.wantsLayer = true
        tint.layer?.cornerRadius = radius
        tint.layer?.masksToBounds = true
        // #0B151D, the prompt bar's fill. Alpha 0.62 over the HUD material
        // composites to the token; at reduced transparency the material is
        // switched off and the tint goes opaque, which is Apple's
        // prefers-reduced-transparency behaviour rather than a blur removal
        // that leaves unreadable text.
        tint.layer?.backgroundColor = NSColor(srgbRed: 11 / 255, green: 21 / 255, blue: 29 / 255, alpha: 0.62).cgColor
        // CONTRACT row 29's treatment: a light hairline rim, no drop shadow.
        tint.layer?.borderWidth = 1
        tint.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        addSubview(tint)

        tile.wantsLayer = true
        tile.layer?.cornerRadius = geometry.scaled(7)
        tile.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        addSubview(tile)

        statusDot.cornerRadius = geometry.scaled(4)
        statusDot.backgroundColor = NSColor.systemGreen.cgColor
        tile.layer?.addSublayer(statusDot)

        // CONTRACT row 42's chrome type: 15 CSS semibold name, 12.5 CSS dimmed
        // subtitle. Apple's typography guidance says not to hand-set tracking
        // at these sizes — the system font already carries the tables.
        titleLabel.font = Self.titleFont(geometry)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.95)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setAccessibilityIdentifier(Self.titleAccessibilityIdentifier)
        addSubview(titleLabel)

        bodyLabel.font = Self.bodyFont(geometry)
        // Flat grey loses too much contrast over a translucent surface. Apple's
        // vibrancy guidance: raise contrast rather than reach for a mid grey.
        bodyLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        bodyLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.maximumNumberOfLines = 1
        bodyLabel.setAccessibilityIdentifier(Self.bodyAccessibilityIdentifier)
        addSubview(bodyLabel)

        applyTransparencySetting()
    }

    func applyTransparencySetting() {
        let reduced = CarouselOverlayMotion.reduceTransparency
        material.isHidden = reduced
        tint.layer?.backgroundColor = NSColor(
            srgbRed: 11 / 255, green: 21 / 255, blue: 29 / 255,
            alpha: reduced ? 1.0 : 0.62
        ).cgColor
    }

    override func layout() {
        super.layout()
        layOutContents()
    }

    func layOutContents() {
        let bounds = CGRect(origin: .zero, size: self.bounds.size)
        material.frame = bounds
        tint.frame = bounds

        let tileSide = geometry.scaled(26)
        let leftInset = geometry.scaled(14)
        tile.frame = CGRect(
            x: leftInset,
            y: (bounds.height - tileSide) / 2,
            width: tileSide,
            height: tileSide
        )
        let dotSide = geometry.scaled(8)
        statusDot.frame = CGRect(
            x: (tileSide - dotSide) / 2,
            y: (tileSide - dotSide) / 2,
            width: dotSide,
            height: dotSide
        )

        let textX = tile.frame.maxX + geometry.scaled(12)
        let textWidth = bounds.width - textX - leftInset
        let titleHeight = geometry.scaled(18)
        let bodyHeight = geometry.scaled(15)
        let stackHeight = titleHeight + geometry.scaled(3) + bodyHeight
        let top = (bounds.height - stackHeight) / 2

        titleLabel.frame = CGRect(x: textX, y: top, width: textWidth, height: titleHeight)
        bodyLabel.frame = CGRect(
            x: textX,
            y: titleLabel.frame.maxY + geometry.scaled(3),
            width: textWidth,
            height: bodyHeight
        )
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }
}
