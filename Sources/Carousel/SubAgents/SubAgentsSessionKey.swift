// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// Identifies the Claude Code session whose sub-agents a card shows.
///
/// Deliberately not `CarouselSession`. U4 needs exactly two strings, and taking
/// only those keeps the sub-agents unit compilable and testable on its own,
/// ahead of U1's card shell. The integrator maps `CarouselSession` to this in
/// one expression, and a surface whose `claudeSessionId` is nil maps to nil —
/// which is what renders the out-of-scope state CONTRACT row 124 requires for
/// Codex and OpenCode surfaces.
struct SubAgentsSessionKey: Sendable, Equatable, Hashable {
    /// The session's working directory with `/` replaced by `-`, which is how
    /// Claude Code names its project directories.
    let projectSlug: String
    /// The Claude Code session id — the directory name under the project.
    let sessionID: String

    init?(projectSlug: String?, sessionID: String?) {
        guard let projectSlug, Self.isPathSafe(projectSlug),
              let sessionID, Self.isPathSafe(sessionID) else { return nil }
        self.projectSlug = projectSlug
        self.sessionID = sessionID
    }

    /// Both values become path components under the data root, so a value that
    /// can traverse out of it is rejected rather than sanitised.
    ///
    /// Rejecting is the safer half of the choice: a mangled name is a directory
    /// nothing looks up, whereas a silently rewritten one reads a real
    /// directory that is not the one asked for. Slugs look like `-home-dawid`
    /// and ids are UUIDs, so nothing legitimate is turned away.
    static func isPathSafe(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }
}
