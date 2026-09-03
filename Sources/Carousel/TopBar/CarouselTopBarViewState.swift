import Foundation

/// Everything the top bar renders, as one value.
///
/// The presentation view is a pure function of this state, so the design
/// direction Dawid has yet to pick changes only the view — never the data path,
/// the liveness rules, or the tests that assert them.
struct CarouselTopBarViewState: Equatable, Sendable {
    var model: ModelState = .unavailable
    var compaction: CompactionState = .unavailable
    var fiveHour: UsageState = .unavailable
    var sevenDay: UsageState = .unavailable
    var liveness: Liveness = .noSession
    var agentActivity: CarouselAgentActivity = .unknown
    /// Non-nil only when the data root could not be read at all (row 117's
    /// degraded state), and names the host that is unreachable.
    var degradedSourceDescription: String?

    /// Row 12.
    enum ModelState: Equatable, Sendable {
        case named(String)
        case unavailable
    }

    /// Row 13.
    enum CompactionState: Equatable, Sendable {
        /// `fraction` is 0...1. `usedTokens` is nil when the payload carried a
        /// percentage but no `current_usage` breakdown to derive a count from.
        case measured(fraction: Double, usedTokens: Int?, windowSize: Int?)
        /// `current_usage` is null — before the first API call and again right
        /// after `/compact`. Explicitly NOT a zero fill.
        case awaitingFirstResponse
        case unavailable
    }

    /// Rows 15 and 120. There is no case that renders a percentage the payload
    /// did not contain.
    enum UsageState: Equatable, Sendable {
        case measured(percent: Double, resetsAt: Date?)
        /// `rate_limits` absent — not a subscriber, or before the first API
        /// response in the session.
        case unavailable
    }

    /// Rows 76, 117, 126.
    enum Liveness: Equatable, Sendable {
        case live
        /// Snapshot older than `StatuslineSnapshotStore.maxAge`.
        case stale(age: TimeInterval, capturedAt: Date)
        /// The centred card is a Claude Code session but has never written a snapshot.
        case noSnapshot
        /// The centred card's session has exited (row 126).
        case deadSession
        /// The centred card is not a Claude Code surface, or there is no centred card.
        case noSession
    }

    /// True when the bar must not show any number as current.
    var suppressesLiveNumbers: Bool {
        switch liveness {
        case .live: false
        case .stale, .noSnapshot, .deadSession, .noSession: true
        }
    }
}

extension CarouselTopBarViewState.UsageState {
    /// Row 75's thresholds. Read literally: H1 asserts a colour at the 50 %,
    /// 80 % and 95 % fixtures, so there is a distinct band on each side of all
    /// three, which needs four bands rather than three.
    enum Severity: Equatable, Sendable { case healthy, elevated, high, critical }

    static func severity(forPercent percent: Double) -> Severity {
        switch percent {
        case ..<50: .healthy
        case ..<80: .elevated
        case ..<95: .high
        default: .critical
        }
    }

    var severity: Severity? {
        switch self {
        case .measured(let percent, _): Self.severity(forPercent: percent)
        case .unavailable: nil
        }
    }
}
