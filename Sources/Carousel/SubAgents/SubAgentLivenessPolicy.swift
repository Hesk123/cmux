// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// The numbers behind "is this sub-agent running", and the reasoning for each.
///
/// The mechanism CONTRACT row 127 requires: the last message in the transcript
/// decides whether the agent has produced its final answer, and the
/// transcript's modification time decides whether that answer is recent enough
/// to trust. Neither signal is sufficient alone — a finished agent and a
/// working one can both end on an assistant message, and a working one blocked
/// in a long tool call writes nothing at all.
struct SubAgentLivenessPolicy: Sendable, Equatable {
    /// How long a transcript may go without a write before its agent stops
    /// counting as running.
    ///
    /// Measured, not guessed: across 9,238 consecutive inter-write gaps in 25
    /// live sub-agent transcripts on the Hive (2026-09-02), p50 was 1.8 s, p90
    /// 12.7 s, p99 75.3 s and p99.5 159.5 s. 120 s sits between p99 and p99.5,
    /// so an agent that is genuinely working keeps its running badge through
    /// better than 99 % of its own quiet periods, while an agent that died mid
    /// tool call surfaces as `unknown` within two minutes instead of lingering
    /// as running forever.
    var runningMaxAge: TimeInterval = 120

    /// How long a terminal-shaped transcript must sit still before it is called
    /// finished.
    ///
    /// An assistant message carrying text and no tool call looks exactly like a
    /// final report — including when it is a paragraph the agent wrote just
    /// before its next tool call. This settle window keeps a working agent from
    /// flickering to `finished` for one frame in the middle of its turn.
    var terminalSettleWindow: TimeInterval = 2

    /// The watcher's poll cadence. A directory watch fires when files are
    /// created or removed, but appending to an existing transcript does not
    /// change the directory, so age transitions and in-place appends are only
    /// visible on a poll. 1 s meets row 127's latency budget.
    var pollInterval: TimeInterval = 1

    /// Directory events arrive in bursts as a spawn writes its transcript and
    /// its metadata; this coalesces them into one scan.
    var coalesceWindow: TimeInterval = 0.15

    /// Ceiling on how far back a transcript is read to find its last complete
    /// JSON line. A single line can be a megabyte of tool output, so the probe
    /// grows its read window rather than assuming one fits.
    var maximumTailBytes: Int = 4 << 20

    static let `default` = SubAgentLivenessPolicy()

    /// Classifies one transcript from its shape and its modification time.
    func activity(
        shape: SubAgentTranscriptProbe.Shape,
        modifiedAt: Date,
        now: Date
    ) -> SubAgentRecord.Activity {
        let age = now.timeIntervalSince(modifiedAt)
        if shape == .terminalAssistantText, age >= terminalSettleWindow { return .finished }
        if age <= runningMaxAge { return .running }
        return .unknown
    }
}
