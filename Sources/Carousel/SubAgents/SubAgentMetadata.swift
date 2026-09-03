import Foundation

/// The sibling `agent-<id>.meta.json` Claude Code writes beside every sub-agent
/// transcript.
///
/// Every field is optional because the file genuinely varies. Measured across
/// the 180 sub-agent files of one live Hive session on 2026-09-02: `agentType`,
/// `description` and `spawnDepth` appeared in all 180; `model` in 147; `name`,
/// `taskKind`, `teamName` in 125; `toolUseId` in 55; `parentAgentId` in only 9.
/// A non-optional field here would fail to decode most of the directory.
struct SubAgentMetadata: Codable, Sendable, Equatable {
    /// The agent definition that was dispatched, e.g. `gemini-researcher`.
    let agentType: String?
    /// The one-line task description the dispatcher wrote.
    let description: String?
    /// The addressable teammate name, when the agent was spawned with one.
    let name: String?
    /// The model alias the agent runs on, e.g. `sonnet`.
    let model: String?
    /// 0 for a named teammate, 1 for a direct child of the session, deeper for
    /// nested spawns.
    let spawnDepth: Int?
    /// The spawning agent's id. Absent for anything the session spawned itself,
    /// which is why nesting is drawn from this field *and* `spawnDepth`.
    let parentAgentId: String?
    /// Present when the agent belongs to a named team.
    let teamName: String?

    /// Returns `nil` rather than throwing: a missing or malformed meta file is
    /// an ordinary state (the file is written a moment after the transcript
    /// opens), and the caller has a defined fallback for it.
    static func read(at url: URL, decoder: JSONDecoder = JSONDecoder()) -> SubAgentMetadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SubAgentMetadata.self, from: data)
    }
}
