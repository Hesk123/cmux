// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import Observation

/// Joins the centred card (row 125) to its statusline snapshot (rows 12, 13, 15)
/// and its liveness (rows 76, 117, 120, 126, 127), and publishes the single value
/// the presentation view renders.
///
/// Everything that decides what the bar is allowed to claim lives here, so the
/// design direction Dawid has yet to pick can be swapped in without touching a
/// liveness rule or invalidating a test.
@MainActor
@Observable
final class CarouselTopBarViewModel {
    private(set) var state = CarouselTopBarViewState()

    private let store: StatuslineSnapshotStore
    private let sessionStates: CarouselSessionStateReader
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private var routing: (any CarouselSessionRouting)?

    init(
        store: StatuslineSnapshotStore,
        sessionStates: CarouselSessionStateReader,
        fileManager: FileManager = .default,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.sessionStates = sessionStates
        self.fileManager = fileManager
        self.now = now
    }

    /// Row 125 — the bar follows the centred card. Binding here and nowhere else
    /// is what makes "navigating changes the top bar" a property of the join
    /// rather than of any particular view.
    func bind(routing: any CarouselSessionRouting) {
        self.routing = routing
        routing.onCentredSessionChanged = { [weak self] session in
            self?.refresh(centredSession: session)
        }
        refresh(centredSession: routing.centredSession)
    }

    func refresh() { refresh(centredSession: routing?.centredSession) }

    func refresh(centredSession: CarouselSession?) {
        state = Self.makeState(
            centredSession: centredSession,
            store: store,
            sessionStates: sessionStates,
            fileManager: fileManager,
            now: now()
        )
    }

    // MARK: - Pure mapping (the whole of the row 12/13/15/76/120/126/127 policy)

    static func makeState(
        centredSession: CarouselSession?,
        store: StatuslineSnapshotStore,
        sessionStates: CarouselSessionStateReader,
        fileManager: FileManager = .default,
        now: Date
    ) -> CarouselTopBarViewState {
        var state = CarouselTopBarViewState()

        // No centred card, or a card that is not a Claude Code surface. The bar
        // says so; it does not keep showing the previous session's numbers.
        guard let session = centredSession, let claudeSessionId = session.claudeSessionId else {
            state.liveness = .noSession
            return state
        }

        let presence = sessionStates.presence(ofSessionId: claudeSessionId)
        let record = store.record(forSessionId: claudeSessionId)

        // Row 126 — the session exited. Its last snapshot is not re-labelled as
        // current, and no percentage survives into this state.
        if case .gone = presence {
            state.liveness = .deadSession
            state.agentActivity = .unknown
            if let record { state.model = modelState(record.snapshot) }
            return state
        }

        // Row 127 — the session registry's own `status` is the primary signal;
        // the transcript's last-entry role is the fallback when the registry is
        // unreadable. Both bound to `.unknown` rather than defaulting to idle.
        state.agentActivity = agentActivity(
            presence: presence,
            record: record,
            fileManager: fileManager,
            now: now
        )

        guard let record else {
            // Row 117 — the source could not be read at all, versus this one
            // session simply never having emitted.
            if store.directoryIsReadable {
                state.liveness = .noSnapshot
            } else {
                state.liveness = .noSnapshot
                state.degradedSourceDescription = store.dataRoot.degradedDescription
            }
            return state
        }

        state.model = modelState(record.snapshot)

        let age = record.age(now: now)
        if age > StatuslineSnapshotStore.maxAge {
            // Row 76 — greyed, capture time shown, never a confidently wrong
            // number. The model name is kept because a model does not go stale;
            // every measured quantity is dropped.
            state.liveness = .stale(age: age, capturedAt: record.capturedAt)
            return state
        }

        state.liveness = .live
        state.compaction = compactionState(record.snapshot)
        let limits = record.snapshot.rateLimits
        state.fiveHour = usageState(limits?.fiveHour)
        state.sevenDay = usageState(limits?.sevenDay)
        return state
    }

    // MARK: - Field mapping

    /// Row 12.
    static func modelState(_ snapshot: StatuslineSnapshot) -> CarouselTopBarViewState.ModelState {
        guard let name = snapshot.model?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else { return .unavailable }
        return .named(name)
    }

    /// Row 13. `current_usage == nil` is the post-`/compact` state and renders
    /// the defined empty state — never a zero fill — even when a stale
    /// `used_percentage` is still present alongside it.
    static func compactionState(_ snapshot: StatuslineSnapshot) -> CarouselTopBarViewState.CompactionState {
        guard let window = snapshot.contextWindow else { return .unavailable }
        guard window.currentUsage != nil else { return .awaitingFirstResponse }
        guard let percentage = window.usedPercentage else { return .unavailable }
        let fraction = min(max(percentage / 100, 0), 1)
        return .measured(
            fraction: fraction,
            usedTokens: window.usedInputTokens,
            windowSize: window.contextWindowSize
        )
    }

    /// Rows 15 and 120. Absent `rate_limits` renders the unavailable state; there
    /// is no path that invents a percentage.
    static func usageState(_ window: StatuslineSnapshot.Window?) -> CarouselTopBarViewState.UsageState {
        guard let window, let percent = window.usedPercentage else { return .unavailable }
        return .measured(percent: min(max(percent, 0), 100), resetsAt: window.resetDate)
    }

    /// Row 127.
    static func agentActivity(
        presence: CarouselSessionPresence,
        record: StatuslineSnapshotRecord?,
        fileManager: FileManager = .default,
        now: Date
    ) -> CarouselAgentActivity {
        if case .present(let sessionState) = presence {
            let activity = sessionState.activity
            if activity != .unknown { return activity }
        }
        return CarouselAgentActivityReader.activity(
            transcriptPath: record?.snapshot.transcriptPath,
            now: now,
            fileManager: fileManager
        )
    }

}
