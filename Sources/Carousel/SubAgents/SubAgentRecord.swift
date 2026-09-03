// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// One sub-agent of a Claude Code session, as read from its transcript and the
/// sibling metadata file.
struct SubAgentRecord: Identifiable, Sendable, Equatable {
    /// What the sub-agent is doing right now, as far as the filesystem can say.
    ///
    /// `unknown` exists on purpose. The transcript directory is a cumulative
    /// history, not a roster, and nothing in it carries a status field
    /// (upstream cmux issue #1152). An agent whose transcript has gone quiet
    /// for longer than the liveness window may be finished, crashed, or blocked
    /// inside a very long tool call, and the honest rendering of that is
    /// `unknown` rather than a confident `idle` (CONTRACT row 127).
    enum Activity: String, Sendable, Equatable, CaseIterable {
        case running
        case finished
        case unknown
    }

    /// The `<id>` of `agent-<id>.jsonl`.
    let id: String
    /// `name` from the metadata, when the agent was spawned with one.
    let name: String?
    /// `agentType` from the metadata.
    let agentType: String?
    /// `description` from the metadata — the task the agent was given.
    let taskDescription: String?
    /// `model` from the metadata.
    let model: String?
    /// `spawnDepth` from the metadata; `0` when the file did not carry one.
    let spawnDepth: Int
    /// `parentAgentId` from the metadata.
    let parentAgentID: String?
    let activity: Activity
    /// The transcript's modification time — the only timestamp the filesystem
    /// offers, and the one liveness is computed from.
    let lastActivity: Date
    /// False when the sibling `.meta.json` was missing or unreadable, so the
    /// UI can show the degraded row rather than pretending the agent is
    /// nameless.
    let hasMetadata: Bool

    /// What the popover shows as the row's title.
    ///
    /// Precedence: the teammate `name`, then `agentType`, then a fallback built
    /// from the id. The fallback is stated rather than left to chance because
    /// the metadata file is written slightly after the transcript, so a
    /// just-spawned agent is briefly nameless every single time.
    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        if let agentType, !agentType.isEmpty { return agentType }
        return SubAgentsStrings.unnamedAgent(shortID)
    }

    /// A short, stable handle for the fallback title and for accessibility.
    var shortID: String {
        String(id.suffix(8))
    }

    /// The row's second line: the task it was given, or a stated blank.
    var displaySubtitle: String {
        if let taskDescription, !taskDescription.isEmpty { return taskDescription }
        return hasMetadata ? SubAgentsStrings.noDescription : SubAgentsStrings.noMetadata
    }

    /// Deterministic ordering: running agents first, then most recent activity,
    /// then id. Ordering must not depend on directory enumeration order, which
    /// the filesystem does not promise.
    static func orderedBefore(_ lhs: SubAgentRecord, _ rhs: SubAgentRecord) -> Bool {
        if lhs.activityRank != rhs.activityRank { return lhs.activityRank < rhs.activityRank }
        if lhs.lastActivity != rhs.lastActivity { return lhs.lastActivity > rhs.lastActivity }
        return lhs.id < rhs.id
    }

    private var activityRank: Int {
        switch activity {
        case .running: 0
        case .unknown: 1
        case .finished: 2
        }
    }
}
