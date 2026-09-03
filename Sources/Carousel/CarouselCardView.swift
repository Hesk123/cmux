// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import SwiftUI

/// One card: the glass shell, its chrome, and the box the terminal or its snapshot
/// occupies. CONTRACT rows 27, 28, 29, 31, 42, 43, 45, 47.
///
/// Flipped, so the CSS-space rects `CarouselMetrics` produces are used directly and
/// nothing has to remember which way `y` runs.
@MainActor
final class CarouselCardView: NSView {
    /// Row 28. `.behindWindow` blending is what makes the card sample the desktop
    /// rather than the app's own backdrop, which is the property row 28's
    /// two-wallpaper test actually discriminates.
    private let material = NSVisualEffectView()
    /// Row 29's bottom hairline, brightest of the four edges.
    private let bottomRim = CALayer()
    /// Row 31. Centre card only.
    private let dragHandle = NSView()
    private let chromeHost: NSHostingView<CarouselCardChromeView>
    /// Where the live terminal mounts, and where a flank's snapshot layer draws.
    /// Kept as its own view so the terminal is never a sibling of the chrome and
    /// can never be laid out by it.
    let terminalBody = CarouselCardBodyView()

    private(set) var session: CarouselSession?
    private var metrics: CarouselMetrics

    /// Whether this card's body is a static image rather than a live terminal.
    ///
    /// Row 115 says exactly one live view exists at rest and none during a switch,
    /// and row 77's grid transition animates card layers directly. U6 asserts on
    /// this that it is only ever moving snapshots, which is the property that makes
    /// a layer transform safe here at all - the section 2.1 portal frame-sync tear
    /// is designed out only while nothing live is on the moving track.
    var isSnapshotLayer: Bool { !terminalBody.hostsLiveTerminal }

    /// This card's identity for the geometry and motion interfaces.
    var cardID: CarouselCardID? { session.map(CarouselCardID.init) }

    override var isFlipped: Bool { true }

    init(metrics: CarouselMetrics) {
        self.metrics = metrics
        chromeHost = NSHostingView(rootView: CarouselCardChromeView(model: Self.placeholderModel(metrics: metrics)))
        super.init(frame: .zero)

        wantsLayer = true
        layer?.masksToBounds = true
        // Row 29: depth is carried by translucency, the hairline and the 0.94 scale
        // step. Stated explicitly rather than left to the default, so a later edit
        // that adds one is visibly a change.
        layer?.shadowOpacity = 0
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        material.blendingMode = .behindWindow
        material.material = .hudWindow
        material.state = .active
        material.translatesAutoresizingMaskIntoConstraints = true
        material.autoresizingMask = [.width, .height]
        addSubview(material)

        chromeHost.translatesAutoresizingMaskIntoConstraints = true
        chromeHost.autoresizingMask = [.width, .height]
        // The card dictates size; never let the hosting view shrink to SwiftUI's
        // ideal, the same rule `WorkspaceCanvasHostView` applies to its mounts.
        chromeHost.sizingOptions = []
        addSubview(chromeHost)

        // Above the chrome host, not below it. The host spans the whole card so its
        // header and footer land in the right bands, and an NSHostingView does not
        // reliably pass a click through its transparent middle - leaving the terminal
        // underneath would make row 50 (click the card, type into that pty)
        // unreachable while every layout assertion still passed.
        terminalBody.translatesAutoresizingMaskIntoConstraints = true
        addSubview(terminalBody)

        bottomRim.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(bottomRim)

        dragHandle.wantsLayer = true
        dragHandle.layer?.backgroundColor = NSColor(calibratedWhite: 0.72, alpha: 0.70).cgColor
        dragHandle.setAccessibilityIdentifier(CarouselAccessibility.dragHandle)
        addSubview(dragHandle)

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityRoleDescription(String(
            localized: "carousel.card.roleDescription",
            defaultValue: "agent session card"
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselCardView is created in code only")
    }

    // MARK: - Content

    func apply(session: CarouselSession, metrics: CarouselMetrics, isCentre: Bool) {
        self.session = session
        self.metrics = metrics
        dragHandle.isHidden = !isCentre
        // The centre card answers to one fixed identifier so a test can find it
        // without knowing which session is there, and carries the session's resource
        // id as its value so the same test can assert *which* session that is. Row 5
        // needs both halves; an identifier that encoded only one of them would make
        // the other unassertable.
        setAccessibilityIdentifier(
            isCentre
                ? CarouselAccessibility.centreCard
                : CarouselAccessibility.card(resourceId: session.resourceId)
        )
        setAccessibilityValue(session.resourceId)
        setAccessibilityLabel(session.displayName)
        // Rule 37's accessibility floor: the card's state has to be readable, not
        // only its identity. Centred-ness and the status pill are both purely
        // visual otherwise.
        setAccessibilityHelp(Self.accessibilityHelp(for: session, isCentre: isCentre))
        chromeHost.rootView = CarouselCardChromeView(model: CarouselCardChromeModel(
            name: session.displayName,
            subtitle: session.subtitle,
            iconSystemName: session.isClaudeCodeSurface ? "sparkles" : "terminal.fill",
            status: session.status,
            signalChips: signalChips,
            showsDragHandle: isCentre,
            iconSide: metrics.headerIconSide,
            nameFontSize: metrics.headerNameFontSize,
            subtitleFontSize: metrics.headerSubtitleFontSize,
            statusFontSize: metrics.statusPillFontSize,
            chipFontSize: metrics.footerChipFontSize
        ))
        needsLayout = true
    }

    /// The card's state in words: whether it is the centred, interactive card, and
    /// what its status pill says.
    static func accessibilityHelp(for session: CarouselSession, isCentre: Bool) -> String {
        let position = isCentre
            ? String(localized: "carousel.card.centred", defaultValue: "Centred")
            : String(localized: "carousel.card.offCentre", defaultValue: "Off centre")
        return "\(position). \(Self.statusDescription(session.status))"
    }

    static func statusDescription(_ status: CarouselSessionStatus) -> String {
        switch status {
        case .busy: String(localized: "carousel.status.busy", defaultValue: "Working")
        case .idle: String(localized: "carousel.status.idle", defaultValue: "Waiting")
        case .stopped: String(localized: "carousel.status.stopped", defaultValue: "Agent stopped")
        case .stale: String(localized: "carousel.status.stale", defaultValue: "Session data stale")
        case .outOfScope: String(localized: "carousel.status.outOfScope", defaultValue: "Not Claude Code")
        }
    }

    /// Row 47's three chips. U1 ships the box and the empty state; the branch,
    /// pull-request and port values are read from cmux's per-surface signals by the
    /// unit that owns that data. An empty array renders the defined empty footer,
    /// which is the honest state and not a placeholder.
    var signalChips: [String] = []

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Rows 27 and 29. The radius is a ratio of the *window*, not of the card,
        // so a flank at 0.94 has the same radius as the centre before its own layer
        // scale is applied - which is what makes the scaled flank's corner read as
        // the same corner.
        layer?.cornerRadius = metrics.cornerRadius
        // Circular, not `.continuous`. U7's fit is a circle at 0.48 px RMS; a
        // squircle of the same nominal radius diverges from that arc by more than
        // row 27's tolerance near the 45-degree point, so the default would fail
        // the corrected row while looking plausible.
        layer?.cornerCurve = .circular

        bottomRim.frame = CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1)

        let handle = metrics.dragHandleRect(inCardRect: bounds)
        dragHandle.frame = handle
        dragHandle.layer?.cornerRadius = handle.height / 2

        // The terminal body sits between the header and the footer. Insets are
        // ratios of the window for the same reason every other box is.
        let headerHeight = metrics.headerIconSide + 28
        let footerHeight = metrics.headerIconSide + 24
        terminalBody.frame = CGRect(
            x: 0,
            y: headerHeight,
            width: bounds.width,
            height: max(0, bounds.height - headerHeight - footerHeight)
        )
    }
}

/// The card's terminal region. Its own view so the live surface mounts into
/// something the chrome cannot lay out, and so a flank's snapshot has a layer to
/// draw into with no other content in it.
@MainActor
final class CarouselCardBodyView: NSView {
    override var isFlipped: Bool { true }

    /// Row 30. A flank draws its cached capture here at the card's own size. The
    /// image is captured at 2x backing scale and drawn at 0.94, so it is
    /// supersampled rather than blurred, which is what makes row 30's "no
    /// additional blur, no opacity change" true by construction.
    private let snapshotLayer = CALayer()

    /// True while `CarouselPaneMount` has a live `GhosttySurfaceScrollView` parented
    /// here. Derived from the view tree rather than from a flag the mount sets, so it
    /// cannot drift out of step with what is actually on screen.
    var hostsLiveTerminal: Bool {
        subviews.contains { $0 is GhosttySurfaceScrollView }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        snapshotLayer.contentsGravity = .resizeAspectFill
        snapshotLayer.magnificationFilter = .trilinear
        snapshotLayer.minificationFilter = .trilinear
        layer?.addSublayer(snapshotLayer)
        setAccessibilityIdentifier(CarouselAccessibility.terminalBody)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselCardBodyView is created in code only")
    }

    private var placeholderHost: NSHostingView<CarouselCardPlaceholderView>?

    /// Shows `image`, or clears the snapshot when nil.
    func setSnapshot(_ image: CGImage?, backingScale: CGFloat) {
        snapshotLayer.contents = image
        snapshotLayer.contentsScale = max(1, backingScale)
        snapshotLayer.isHidden = image == nil
    }

    var hasSnapshot: Bool { snapshotLayer.contents != nil }

    /// Row 10's defined no-capture state. Shown only when there is no snapshot and
    /// no live view - never on top of either, so a real capture always wins.
    func setPlaceholder(_ session: CarouselSession?) {
        guard let session else {
            placeholderHost?.removeFromSuperview()
            placeholderHost = nil
            return
        }
        let view = CarouselCardPlaceholderView(session: session)
        if let host = placeholderHost {
            host.rootView = view
            return
        }
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.sizingOptions = []
        host.frame = bounds
        addSubview(host)
        placeholderHost = host
    }

    var showsPlaceholder: Bool { placeholderHost != nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        // Layer frames must not inherit the ambient animation from a running
        // switch; a resize during a switch would otherwise interpolate the
        // snapshot's frame and read as a wobble.
        CATransaction.setDisableActions(true)
        snapshotLayer.frame = bounds
        CATransaction.commit()
        placeholderHost?.frame = bounds
    }
}

private extension CarouselCardView {
    static func placeholderModel(metrics: CarouselMetrics) -> CarouselCardChromeModel {
        CarouselCardChromeModel(
            name: "",
            subtitle: "",
            iconSystemName: "terminal.fill",
            status: .outOfScope,
            signalChips: [],
            showsDragHandle: false,
            iconSide: metrics.headerIconSide,
            nameFontSize: metrics.headerNameFontSize,
            subtitleFontSize: metrics.headerSubtitleFontSize,
            statusFontSize: metrics.statusPillFontSize,
            chipFontSize: metrics.footerChipFontSize
        )
    }
}
