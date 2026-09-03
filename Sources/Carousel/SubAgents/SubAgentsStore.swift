import Foundation
import Observation

/// The observable state behind the sub-agents chip and its popover.
///
/// Holds the last scan, the outline derived from it, and the two counts the
/// chip shows. Derivation happens here, once per scan, and never inside a view
/// body — `body` runs far more often than the data changes, and cmux has an
/// existing 100 % CPU spin to show for state written from a body.
@MainActor
@Observable
final class SubAgentsStore {
    /// The last reading of the directory.
    private(set) var scan: SubAgentScan

    /// The popover's list, parents before their children.
    private(set) var rows: [SubAgentOutlineRow] = []

    /// How many mounted workspaces were excluded from the card list because
    /// they are not mounted (CONTRACT rows 132 and D-9).
    ///
    /// The carousel iterates mounted workspaces only, because cmux bounds
    /// memory with a background-retention policy and force-mounting every
    /// workspace to fill a carousel would defeat the policy on purpose. The
    /// count is surfaced as a badge so the excluded surfaces do not simply
    /// vanish. Supplied by the card list; U4 renders it.
    var excludedWorkspaceCount: Int = 0

    private(set) var root: CarouselDataRoot
    private(set) var session: SubAgentsSessionKey?

    private let policy: SubAgentLivenessPolicy
    private var watcher: SubAgentDirectoryWatcher?

    init(
        root: CarouselDataRoot = .resolve(),
        session: SubAgentsSessionKey? = nil,
        policy: SubAgentLivenessPolicy = .default,
        excludedWorkspaceCount: Int = 0
    ) {
        self.root = root
        self.session = session
        self.policy = policy
        self.excludedWorkspaceCount = excludedWorkspaceCount
        self.scan = .empty(availability: session == nil ? .outOfScope : .ready, scannedAt: .distantPast)
    }

    /// Whether the chip opens anything.
    ///
    /// Everything except an out-of-scope surface has a panel worth reading: an
    /// empty session says so, a missing root names the path it looked in, and a
    /// stale mirror names the host that went quiet. Disabling the chip whenever
    /// the list happened to be empty made those states unreachable — the empty
    /// state existed and nothing could open it.
    var isInteractive: Bool {
        scan.availability != .outOfScope
    }

    /// Begins watching, and re-points the watcher when the centred card changes.
    func start() {
        let watcher = watcher ?? SubAgentDirectoryWatcher(policy: policy) { [weak self] scan in
            self?.apply(scan)
        }
        self.watcher = watcher
        watcher.watch(root: root, session: session)
    }

    func stop() {
        watcher?.stop()
    }

    /// Follows the centred card. Called by the routing adapter each time the
    /// carousel settles on a different session.
    func update(root: CarouselDataRoot? = nil, session: SubAgentsSessionKey?) {
        if let root { self.root = root }
        self.session = session
        if watcher == nil {
            start()
        } else {
            watcher?.watch(root: self.root, session: session)
        }
    }

    private func apply(_ scan: SubAgentScan) {
        self.scan = scan
        rows = SubAgentOutline.rows(for: scan.records)
    }

    /// Test seam: applies a scan without a watcher, so the view layer can be
    /// exercised against a fixed reading.
    func applyForTesting(_ scan: SubAgentScan) {
        apply(scan)
    }
}

#if DEBUG
extension SubAgentsStore {
    /// Preview-only store. Fixtures never reach a shipping code path
    /// (CONTRACT row 85).
    static var preview: SubAgentsStore {
        let store = SubAgentsStore(
            root: CarouselDataRoot(
                url: URL(fileURLWithPath: "/tmp", isDirectory: true),
                source: .environmentOverride,
                freshness: .unknown
            ),
            session: SubAgentsSessionKey(projectSlug: "-home-dawid", sessionID: "preview"),
            excludedWorkspaceCount: 2
        )
        store.applyForTesting(
            SubAgentScan(
                availability: .ready,
                records: SubAgentRecord.previewRecords,
                scannedAt: Date(),
                freshness: .unknown
            )
        )
        return store
    }
}
#endif
