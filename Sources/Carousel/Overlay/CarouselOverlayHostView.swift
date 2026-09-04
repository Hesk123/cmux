// Modified 2026-09-02 for the cmux carousel UI build, unit U6 (grid mode, toast,
// exceeds-source transitions). CONTRACT rows 37, 80, 83.
// Modified files in this build carry this notice per GPL-3.0 section 5(a).

import AppKit
import QuartzCore
import SwiftUI

/// Hosts the two overlay surfaces U6 owns — the grid selection ring and the
/// toast — above the carousel track, and converts the contract's top-left
/// viewport coordinates into layer coordinates.
///
/// It does **not** host the cards. Those are U1's, and the grid transition
/// drives them where they already live rather than reparenting them, so a live
/// terminal is never detached and re-attached by a mode toggle.
///
/// The flip is done explicitly instead of relying on `isFlipped` propagating to
/// the backing layer, because the whole overlay's correctness rests on it and a
/// silent AppKit change would move every rect by the viewport height with no
/// compile error. `viewportToLayer(_:)` is asserted directly by the tests.
/// Subclassable for the grid mount (the representable creates the mounted
/// variant while the bare host keeps its tested behaviour untouched).
@MainActor
class CarouselOverlayHostView: NSView {
    static let accessibilityIdentifierValue = "carousel.overlay.host"

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityIdentifier(Self.accessibilityIdentifierValue)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselOverlayHostView is created in code only")
    }

    /// Overlay chrome must never swallow a click meant for a card or the
    /// terminal underneath. Subviews that genuinely want clicks (the toast)
    /// still receive them, because `hitTest` on a subview is consulted first.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// The layer the grid transition and the ring live in. Cards supplied by U1
    /// may sit in any sublayer of this one; conversion goes through
    /// `CALayer.convert` so the track's own transform is accounted for.
    var overlayLayer: CALayer? { layer }

    /// Converts a rect in the contract's top-left viewport coordinates into
    /// this view's backing-layer coordinates.
    /// Reads the backing layer's own flag rather than the view's `isFlipped`,
    /// because it is the layer flag that governs where a manually added
    /// sublayer lands. AppKit sets it for a flipped layer-backed view, and the
    /// tests assert a real sublayer's window-space position rather than trust
    /// that, so this stays honest if the AppKit behaviour ever changes.
    func viewportToLayer(_ rect: CGRect) -> CGRect {
        guard let layer, !layer.isGeometryFlipped else { return rect }
        return CGRect(
            x: rect.minX,
            y: layer.bounds.height - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func viewportToLayer(_ point: CGPoint) -> CGPoint {
        guard let layer, !layer.isGeometryFlipped else { return point }
        return CGPoint(x: point.x, y: layer.bounds.height - point.y)
    }
}

// MARK: - Grid mount (U6 integration, 2026-09-04)

/// Accessibility identifiers for the grid chrome. Checked first: neither
/// `CarouselAccessibility` (in `CarouselCardChromeView.swift`) nor any
/// `CarouselGridAccessibility` type exists anywhere in `Sources/` — so these
/// are defined here, in the U6-owned overlay file, rather than editing the
/// U1-owned chrome file. Values match the contract in the task brief.
enum CarouselGridAccessibility {
    static let close = "carousel.grid.close"
    static let commit = "carousel.grid.commit"
    static func card(slot: Int) -> String { "carousel.grid.card.\(slot)" }
}

extension Notification.Name {
    /// Window-scoped grid-toggle request, mirroring `CarouselModeState`
    /// / `CarouselNavigationRouter`. Posted by external entry points that
    /// cannot reach the mount directly (menu items, command palette, UI
    /// tests); the mount observes it. The ^M chord itself is caught by the
    /// mount's local key monitor and toggles directly, not via this.
    static let carouselGridToggle = Notification.Name("com.cmux.carousel.gridToggle")
}

/// Shared toggle path for entry points that cannot reach the mount directly
/// (menu items, command palette, UI tests).
@MainActor
enum CarouselGridToggle {
    static func post(window: NSWindow?) {
        NotificationCenter.default.post(name: .carouselGridToggle, object: window)
    }

    /// Same addressing rule as `CarouselModeState.toggleApplies`: an explicit
    /// window targets exactly it, a nil object means the key window.
    static func applies(_ notification: Notification, to window: NSWindow?) -> Bool {
        guard let window else { return false }
        guard let target = notification.object as? NSWindow else {
            return window.isKeyWindow
        }
        return target === window
    }
}

/// Owns the grid presenter and its chrome, and feeds both from the track.
///
/// Mount design:
/// * Owner: `CarouselGridOverlayView` (below) creates and holds one mount for
///   the lifetime of the carousel branch. The mount owns a
///   `CarouselGridPresenter`; nothing else retains the presenter.
/// * Lifecycle: `sync(track:)` rebuilds geometry + presenter cards from the
///   track on every representable update and on layout (resize). `toggle()`
///   flips modes. Buttons, catchers and the ring are hidden unless
///   `mode == .grid`.
/// * Cards source: the track's *visible* card views (`track.cards`, keyed by
///   slot). Each presenter card wraps the view's own layer plus its rest rect
///   (`metrics.rect(forSlot:)`), so the transition never reparents a live
///   terminal. Sessions with no laid-out view have no layer to drive and are
///   not shown — a full 6-card grid needs a U1 hook exposing hidden sessions'
///   layers (see limitations in the handoff).
/// * Geometry: single-expression conversion from U1's metrics —
///   `CarouselOverlayGeometry(viewport: <overlay bounds>,
///   centreCardRect: metrics.rect(forSlot: 0), cardCornerRadius:
///   metrics.cornerRadius)`.
/// * Chord: a local key-down monitor matches `^M` through the *same* path the
///   focus coordinator uses (`CarouselKeyRouter.route` with
///   `CarouselShortcutBindings.live`), so a Settings rebind is honoured with
///   no AppDelegate edit. In grid mode the same monitor owns plain arrows /
///   Return / Esc for selection. Everything else passes through untouched, so
///   prompt-bar typing is never disturbed.
@MainActor
final class CarouselGridMount {
    private weak var host: CarouselGridOverlayView?
    private let presenter: CarouselGridPresenter
    /// Presenter index -> track slot, rebuilt on every sync.
    private var gridSlots: [Int] = []
    private weak var track: CarouselTrackView?
    private nonisolated(unsafe) var eventMonitor: Any?
    private nonisolated(unsafe) var toggleObserver: NSObjectProtocol?
    private var closeButton: NSButton?
    private var commitButton: NSButton?
    private var cardCatchers: [NSButton] = []

    init(host: CarouselGridOverlayView) {
        self.host = host
        // Stand-in until the first sync replaces it; replaced synchronously
        // in `sync(track:)` before anything is visible.
        let geometry = CarouselOverlayGeometry.contractDefault()
        self.presenter = CarouselGridPresenter(geometry: geometry, host: host)
        installEventMonitor()
        toggleObserver = NotificationCenter.default.addObserver(
            forName: .carouselGridToggle,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let host = self.host else { return }
                guard CarouselGridToggle.applies(notification, to: host.window) else { return }
                self.toggle()
            }
        }
        rebuildChrome()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let toggleObserver {
            NotificationCenter.default.removeObserver(toggleObserver)
        }
    }

    var isGrid: Bool { presenter.mode == .grid }

    // MARK: - Sync

    /// Rebuilds geometry and presenter cards from the track. Called from the
    /// representable's `updateNSView` and from the overlay view's `layout()`.
    func sync(track: CarouselTrackView?) {
        self.track = track
        guard let host, let track else {
            presenter.setCards([])
            gridSlots = []
            rebuildChrome()
            return
        }
        let viewport = host.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        // Never disturb a running flight: a ContentView re-render landing
        // mid-transition would otherwise snap every card via the
        // animated:false paths below.
        guard !presenter.isTransitioning else {
            rebuildChrome()
            return
        }
        let geometry = CarouselOverlayGeometry(
            viewport: viewport,
            centreCardRect: track.metrics.rect(forSlot: 0),
            cardCornerRadius: track.metrics.cornerRadius
        )
        presenter.setGeometry(geometry)
        refreshCardsFromTrack(track)
        rebuildChrome()
    }

    /// Re-reads the track's visible card views into presenter cards, preserving
    /// the centred card as the selected slot. Slot order is stable (sorted),
    /// so presenter indices map 1:1 onto `gridSlots` for commit.
    private func refreshCardsFromTrack(_ track: CarouselTrackView) {
        let slots = track.cards.keys.sorted()
        var cards: [CarouselGridPresenter.Card] = []
        var mappedSlots: [Int] = []
        for slot in slots {
            guard let view = track.cards[slot], let layer = view.layer else { continue }
            cards.append(CarouselGridPresenter.Card(
                layer: layer,
                carouselRect: track.metrics.rect(forSlot: slot)
            ))
            mappedSlots.append(slot)
        }
        gridSlots = mappedSlots
        presenter.setCards(cards)
        // Only when not in grid: a sync landing mid-grid (SwiftUI re-render,
        // resize) must not yank the ring back to centre under the user.
        if presenter.mode != .grid,
           let centreIndex = mappedSlots.firstIndex(of: 0) {
            presenter.setSelectedSlot(centreIndex)
        }
    }

    // MARK: - Mode

    func toggle() {
        guard track != nil else { return }
        if isGrid {
            exitCommit()
        } else {
            enter()
        }
    }

    private func enter() {
        guard let track else { return }
        sync(track: track)
        // No gridSlots guard: an empty track still opens the grid (buttons +
        // empty block) rather than swallowing the chord. The carousel shows
        // empty states instead of nothing everywhere else; the grid is not
        // an exception.
        presenter.setMode(.grid, animated: true)
        rebuildChrome()
    }

    /// Grid exit, honouring the recentre contract on
    /// `CarouselGeometryProviding`: the track recentres on the selected
    /// session *synchronously with its own layout suppressed*, so the model
    /// moves while the views stay where the presenter put them; the presenter
    /// then glides each card from its grid rect back to its slot frame, and a
    /// settle pass re-seats content once the flight lands.
    func exitCommit() {
        guard let track else {
            presenter.setMode(.carousel, animated: true)
            rebuildChrome()
            return
        }
        if let session = selectedSession(track: track) {
            track.withTrackAnimationSuppressed {
                _ = track.recentre(to: CarouselCardID(session))
                refreshCardsFromTrack(track)
            }
        }
        presenter.setMode(.carousel, animated: true)
        rebuildChrome()
        // `recentre` reseated nothing (suppressed) and the glide targets the
        // slot frames, so once the flight lands the views show the right
        // sessions in the right places after one settle. Fires after the
        // longer of the full and reduced-motion transitions.
        let delay: CFTimeInterval = CarouselOverlayMotion.reduceMotion
            ? CarouselOverlayMotion.reducedCrossFade + 0.05
            : CarouselOverlayMotion.gridTransition + 0.05
        Task { @MainActor [weak track] in
            try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
            track?.layoutSubtreeIfNeeded()
        }
    }

    /// The selected presenter slot resolved back to a session via the track's
    /// own modular indexing (rows 51/57: wrap, never clamp).
    private func selectedSession(track: CarouselTrackView) -> CarouselSession? {
        guard !gridSlots.isEmpty, !track.sessions.isEmpty else { return nil }
        let clamped = min(max(presenter.selectedSlot, 0), gridSlots.count - 1)
        let slot = gridSlots[clamped]
        guard let index = CarouselMetrics.sessionIndex(
            forSlot: slot,
            centre: track.centredSlotIndex,
            sessionCount: track.sessions.count
        ), track.sessions.indices.contains(index) else { return nil }
        return track.sessions[index]
    }

    // MARK: - Chrome (x/G buttons + card click catchers)

    private func rebuildChrome() {
        guard let host else { return }
        if closeButton == nil {
            closeButton = host.makeGridCircleButton(title: "×", identifier: CarouselGridAccessibility.close)
            closeButton?.target = self
            closeButton?.action = #selector(didTapClose)
            if let button = closeButton { host.addSubview(button) }
        }
        if commitButton == nil {
            commitButton = host.makeGridCircleButton(title: "G", identifier: CarouselGridAccessibility.commit)
            commitButton?.target = self
            commitButton?.action = #selector(didTapCommit)
            if let button = commitButton { host.addSubview(button) }
        }
        // Card click catchers: one transparent button per grid rect. The real
        // card views have no click-to-select path (U1/U3 unmounted), and the
        // host deliberately passes clicks through, so these are the commit
        // mechanism for pointer input. Removed and rebuilt on every sync so
        // they track the layout exactly.
        cardCatchers.forEach { $0.removeFromSuperview() }
        cardCatchers = []
        let visible = isGrid && track != nil
        closeButton?.isHidden = !visible
        commitButton?.isHidden = !visible
        guard visible else {
            host.positionGridButtons(close: closeButton, commit: commitButton, visible: false)
            return
        }
        host.positionGridButtons(close: closeButton, commit: commitButton, visible: true)
        for index in gridSlots.indices {
            let rect = presenter.targetRect(forSlot: index)
            let catcher = NSButton(title: "", target: self, action: #selector(didTapCard(_:)))
            catcher.tag = index
            catcher.isBordered = false
            catcher.imagePosition = .noImage
            catcher.title = ""
            catcher.wantsLayer = true
            catcher.layer?.backgroundColor = NSColor.clear.cgColor
            catcher.frame = rect
            catcher.setAccessibilityIdentifier(CarouselGridAccessibility.card(slot: index))
            catcher.setAccessibilityElement(true)
            catcher.setAccessibilityRole(.button)
            catcher.setAccessibilityLabel("Select session \(index + 1)")
            catcher.isHidden = false
            host.addSubview(catcher, positioned: .below, relativeTo: closeButton)
            cardCatchers.append(catcher)
        }
    }

    @objc private func didTapClose() {
        exitCommit()
    }

    @objc private func didTapCommit() {
        exitCommit()
    }

    @objc private func didTapCard(_ sender: NSButton) {
        presenter.setSelectedSlot(sender.tag)
        exitCommit()
    }

    // MARK: - Keys

    private static let returnKeyCode: UInt16 = 36

    private func installEventMonitor() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let host = self.host, host.window != nil else { return event }
                guard event.window === host.window else { return event }
                return self.handleKeyDown(event)
            }
        }
    }

    /// Returns nil when the event is consumed.
    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        // Grid selection keys first: in grid mode plain arrows drive the ring
        // (the prompt bar keeps focus per D-1, so they would otherwise edit
        // the composed line), Return commits, Esc exits.
        if isGrid {
            let flags = ShortcutStroke.normalizedModifierFlags(from: event.modifierFlags)
            if flags.isEmpty {
                switch event.keyCode {
                case CarouselKeyRouter.KeyCode.leftArrow:
                    presenter.moveSelection(by: -1); return nil
                case CarouselKeyRouter.KeyCode.rightArrow:
                    presenter.moveSelection(by: 1); return nil
                case CarouselKeyRouter.KeyCode.upArrow:
                    presenter.moveSelectionByRow(-1); return nil
                case CarouselKeyRouter.KeyCode.downArrow:
                    presenter.moveSelectionByRow(1); return nil
                case CarouselKeyRouter.KeyCode.escape:
                    exitCommit(); return nil
                case Self.returnKeyCode:
                    exitCommit(); return nil
                default:
                    break
                }
            }
        }
        // The ^M chord through the shared router, honouring a Settings rebind.
        let routing = CarouselKeyRouter.route(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            eventCharacter: event.charactersIgnoringModifiers,
            focusOwner: .promptBar,
            bindings: .live
        )
        switch routing {
        case .toggleGrid:
            toggle()
            return nil
        case .navigateCarousel where isGrid:
            // Chorded arrows move the ring while the grid is up rather than
            // sliding the carousel underneath it.
            if event.keyCode == CarouselKeyRouter.KeyCode.leftArrow { presenter.moveSelection(by: -1); return nil }
            if event.keyCode == CarouselKeyRouter.KeyCode.rightArrow { presenter.moveSelection(by: 1); return nil }
            if event.keyCode == CarouselKeyRouter.KeyCode.upArrow { presenter.moveSelectionByRow(-1); return nil }
            if event.keyCode == CarouselKeyRouter.KeyCode.downArrow { presenter.moveSelectionByRow(1); return nil }
            return event
        default:
            return event
        }
    }
}

/// The overlay view that hosts the mount. A subclass (not a same-class
/// extension) so the representable below can create the mounted variant while
/// the bare `CarouselOverlayHostView` keeps its tested behaviour untouched.
@MainActor
final class CarouselGridOverlayView: CarouselOverlayHostView {
    private var mount: CarouselGridMount?
    private weak var centre: CarouselCentreAdapter?

    /// Click-through: this view spans the whole deck even when the grid is
    /// closed, and a frontmost catch-all would swallow every chip/popover/
    /// prompt click beneath it (bisected via the popover UI test). The
    /// background itself therefore never takes clicks; the x/G buttons and
    /// card catchers (visible only in grid mode) still hit-test normally.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    func bind(centre: CarouselCentreAdapter) {
        self.centre = centre
        if mount == nil { mount = CarouselGridMount(host: self) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncFromCentre()
    }

    override func layout() {
        super.layout()
        syncFromCentre()
    }

    func syncFromCentre() {
        guard let mount, let centre else { return }
        mount.sync(track: centre.rootView?.track)
    }

    // MARK: - Grid chrome layout

    /// Small circular dark buttons below the grid block centre, in the visual
    /// language of the deck arrows (`ContentView.carouselDeckArrow`: 40 pt
    /// circle, black 0.45) with a keycap-hint hairline so they read as
    /// keyboard-adjacent chrome. Reference: x + G row below centre; toast is
    /// untouched and stays top-right.
    func makeGridCircleButton(title: String, identifier: String) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.font = .systemFont(ofSize: 15, weight: .semibold)
        button.contentTintColor = .white.withAlphaComponent(0.85)
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        button.layer?.cornerRadius = 20
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        button.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        button.setAccessibilityIdentifier(identifier)
        button.setAccessibilityElement(true)
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(identifier == CarouselGridAccessibility.close ? "Close grid" : "Select session")
        button.isHidden = true
        return button
    }

    func positionGridButtons(close: NSButton?, commit: NSButton?, visible: Bool) {
        guard visible, let close, let commit else { return }
        // Below the carousel card's vertical centre, matching the deck-arrow
        // row's anchor (card maxY + 16) so the row does not jump between modes.
        let track = centre?.rootView?.track
        let anchorY: CGFloat
        if let track {
            anchorY = track.metrics.rect(forSlot: 0).maxY + 16
        } else {
            anchorY = bounds.midY + 16
        }
        let midX = bounds.midX
        close.frame = CGRect(x: midX - 40 - 6, y: anchorY, width: 40, height: 40)
        commit.frame = CGRect(x: midX + 6, y: anchorY, width: 40, height: 40)
    }
}

/// SwiftUI seam for the grid overlay. Created and updated from the carousel
/// branch of `ContentView.terminalContent` (see the paste-ready snippet in the
/// handoff); reads the live track through `carouselCentre.rootView?.track`,
/// so no Root/Track/Host edit is needed.
struct CarouselGridOverlayRepresentable: NSViewRepresentable {
    let centre: CarouselCentreAdapter

    func makeNSView(context: Context) -> CarouselGridOverlayView {
        let view = CarouselGridOverlayView(frame: .zero)
        view.bind(centre: centre)
        return view
    }

    func updateNSView(_ nsView: CarouselGridOverlayView, context: Context) {
        nsView.bind(centre: centre)
        nsView.syncFromCentre()
    }
}
