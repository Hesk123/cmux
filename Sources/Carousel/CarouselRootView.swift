// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import SwiftUI

/// The carousel's AppKit root: owns the track, the one live mount, the snapshot
/// cache, and the swap protocol between them. CONTRACT rows 17, 26, 50, 85, 115,
/// 116, 132.
///
/// Row 17's chrome-less posture is a property of this view drawing no title bar and
/// no background band of its own: the only thing between the macOS menu bar and the
/// card row is whatever cmux's own chrome already puts there.
@MainActor
final class CarouselRootView: NSView, CarouselSessionRouting {
    let track: CarouselTrackView
    private let mount: CarouselPaneMount
    private let cache: CarouselSnapshotCache
    private let coordinator: CarouselLiveSwapCoordinator
    /// Owned here rather than by the SwiftUI shell: the read touches the file system,
    /// and `swiftui-pro` is explicit that work which can leave `body` should.
    private let sessionModel: CarouselSessionModel
    private var emptyStateHost: NSHostingView<CarouselEmptyStateView>?
    private var refreshTimer: Timer?

    /// Resolves a session back to its panel. Injected rather than reached for, so the
    /// root holds no store reference and this view can be built in a test.
    var panelForSession: (CarouselSession) -> TerminalPanel? = { _ in nil }

    /// Installed by U2. Given a signed slot step it runs row 52's 300 ms ease-out and
    /// row 54's recoil, then calls `settle`. Nil until U2 lands, and the move is
    /// instantaneous rather than a hand-rolled tween nobody asked for.
    var trackAnimator: ((_ step: Int, _ settle: @escaping () -> Void) -> Void)?

    var onCentredSessionChanged: ((CarouselSession?) -> Void)?

    override var isFlipped: Bool { true }

    init(metrics: CarouselMetrics) {
        // Built as locals and then assigned: reading `self.mount` to construct the
        // coordinator before `super.init` is not allowed, and an inline property
        // initialiser would force exactly that.
        let mount = CarouselPaneMount()
        let cache = CarouselSnapshotCache()
        self.mount = mount
        self.cache = cache
        coordinator = CarouselLiveSwapCoordinator(mount: mount, cache: cache)
        track = CarouselTrackView(metrics: metrics)
        sessionModel = CarouselSessionModel(
            liveness: CarouselSessionLiveness(root: CarouselDataRoot())
        )
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityIdentifier(CarouselAccessibility.root)
        addSubview(track)

        track.onCentredSessionChanged = { [weak self] session in
            guard let self else { return }
            self.coordinator.settleAtRest(track: self.track, panelForSession: self.panelForSession)
            self.onCentredSessionChanged?(session)
        }
        track.onCardsChanged = { [weak self] in
            guard let self, !self.coordinator.isSwitching else { return }
            self.coordinator.settleAtRest(track: self.track, panelForSession: self.panelForSession)
        }
        mount.onTerminalFocus = { [weak self] panelId in
            self?.onTerminalFocus?(panelId)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CarouselRootView is created in code only")
    }

    /// Row 114. Clicking a card hands focus to that terminal; U3's focus coordinator
    /// listens here and returns focus to the prompt bar on Esc.
    var onTerminalFocus: ((UUID) -> Void)?

    // MARK: - CarouselSessionRouting

    var sessions: [CarouselSession] { track.sessions }
    var centredSession: CarouselSession? { track.centredSession }

    func navigate(_ direction: CarouselNavigationDirection) {
        guard sessions.count > 1 else { return }
        // Transition 2 first, on this frame, using only warm captures.
        coordinator.beginSwitch(track: track)
        track.navigate(direction) { [weak self] step in
            guard let self else { return }
            guard let animator = self.trackAnimator else {
                self.track.settle(step: step)
                return
            }
            animator(step) { [weak self] in
                self?.track.settle(step: step)
            }
        }
    }

    // MARK: - Content

    /// One read of the world per update, so the card list and the empty-state reason
    /// can never describe two different instants.
    ///
    /// - Parameters:
    ///   - workspaces: every workspace in the window, in `TabManager` order.
    ///   - mountedWorkspaceIds: the mounted subset. D-9 scopes the carousel to it, and
    ///     this value is only ever read - nothing here force-mounts a workspace, because
    ///     the background-retention policy bounds memory on purpose.
    func update(
        workspaces: [Workspace],
        mountedWorkspaceIds: Set<UUID>,
        panelForSession: @escaping (CarouselSession) -> TerminalPanel?
    ) {
        self.panelForSession = panelForSession
        let snapshot = sessionModel.snapshot(
            workspaces: workspaces,
            mountedWorkspaceIds: mountedWorkspaceIds
        )
        track.update(sessions: snapshot.sessions, metrics: CarouselMetrics(viewport: bounds.size))
        track.isHidden = snapshot.sessions.isEmpty
        setEmptyState(snapshot.sessions.isEmpty ? Self.emptyReason(for: snapshot) : nil)
        if snapshot.sessions.isEmpty {
            mount.unmount()
        } else {
            coordinator.settleAtRest(track: track, panelForSession: panelForSession)
        }
    }

    /// Row 85 asserts the empty state against a genuinely empty root **and** against a
    /// host that has a live session but is unreachable, so the two must not collapse
    /// into one rendering.
    static func emptyReason(for snapshot: CarouselSessionSnapshot) -> CarouselEmptyStateView.Reason {
        if !snapshot.isMirrorFresh {
            return .mirrorStale(age: snapshot.mirrorAge ?? CarouselDataRoot.stalenessBound)
        }
        if snapshot.unmountedAgentSurfaceCount > 0 {
            return .allSurfacesUnmounted(count: snapshot.unmountedAgentSurfaceCount)
        }
        return .noAgentSurfaces
    }

    private func setEmptyState(_ reason: CarouselEmptyStateView.Reason?) {
        guard let reason else {
            emptyStateHost?.removeFromSuperview()
            emptyStateHost = nil
            return
        }
        let view = CarouselEmptyStateView(reason: reason)
        if let host = emptyStateHost {
            host.rootView = view
            return
        }
        let host = NSHostingView(rootView: view)
        host.translatesAutoresizingMaskIntoConstraints = true
        host.autoresizingMask = [.width, .height]
        host.frame = bounds
        host.sizingOptions = []
        addSubview(host)
        emptyStateHost = host
    }

    // MARK: - Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTimer?.invalidate()
        guard window != nil else {
            refreshTimer = nil
            mount.unmount()
            return
        }
        // Transition 1's warm-keeping half. `Timer` rather than a display link:
        // AGENTS.md forbids an app-level display link near a terminal surface,
        // and 4 Hz does not need vsync.
        let timer = Timer.scheduledTimer(
            withTimeInterval: CarouselSnapshotCache.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.coordinator.refreshCentreSnapshot(track: self.track, window: self.window)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    /// Hands the terminal back and stops the refresh. Called by the representable's
    /// `dismantleNSView`, so leaving carousel mode never strands a surface.
    func teardown() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        mount.unmount()
    }

    override func layout() {
        super.layout()
        track.frame = bounds
        emptyStateHost?.frame = bounds
    }

    // MARK: - Test seams

    /// Row 115's assertion reads this rather than walking the view tree: exactly one
    /// live libghostty view at rest, zero during a switch.
    var attachedLiveViewCount: Int { coordinator.attachedLiveViewCount }
}
