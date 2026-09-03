// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation

/// One reading of a session's sub-agent directory.
struct SubAgentScan: Sendable, Equatable {
    /// Why the list is what it is. An empty list has several distinct causes
    /// and the UI must not collapse them: a session with no sub-agents yet, a
    /// surface that is not a Claude Code session at all, and a data root that
    /// is not there are three different things to say.
    enum Availability: Sendable, Equatable {
        /// The directory was read. `records` is authoritative, empty included.
        case ready
        /// The surface is not a Claude Code session, so there is no
        /// `~/.claude` path to read (CONTRACT row 124). cmux also hosts Codex
        /// and OpenCode surfaces, and neither writes these files.
        case outOfScope
        /// The configured data root does not exist. Carries the path so the
        /// degraded state can name it rather than showing a bare empty list.
        case rootMissing(String)
        /// The root exists but this session has no `subagents/` directory,
        /// which is the normal state until the session spawns its first agent.
        case sessionMissing
    }

    let availability: Availability
    /// Ordered by `SubAgentRecord.orderedBefore`.
    let records: [SubAgentRecord]
    let scannedAt: Date
    /// How fresh the mirror behind this reading is, computed in the same
    /// off-main pass from the stamp `tools/carousel-mirror/pull-claude-data.sh`
    /// writes (CONTRACT row 117). A bridge that has stopped leaves data that
    /// parses perfectly and is simply old, and a carousel that shows it as live
    /// is worse than one that says it is stale.
    let freshness: CarouselDataRoot.Freshness

    /// What the chip counts.
    ///
    /// Running only. The directory is a cumulative history — one live session
    /// on the Hive held 180 transcripts — so counting files would report a
    /// number that only ever grows and means nothing (CONTRACT row 71).
    var runningCount: Int {
        records.count(where: { $0.activity == .running })
    }

    /// Same reading, ignoring `scannedAt`: the watcher polls every second and
    /// every scan carries a fresh timestamp, so plain equality never holds and
    /// applying unconditionally re-renders the chip every second forever — the
    /// app never idles and the accessibility tree churns under every snapshot.
    /// The store drops readings that are the same by this measure; a real
    /// change still propagates within one poll.
    func isSameReading(as other: SubAgentScan) -> Bool {
        availability == other.availability
            && records == other.records
            && freshness == other.freshness
    }

    static func empty(
        availability: Availability,
        scannedAt: Date,
        freshness: CarouselDataRoot.Freshness = .unknown
    ) -> SubAgentScan {
        SubAgentScan(
            availability: availability,
            records: [],
            scannedAt: scannedAt,
            freshness: freshness
        )
    }
}
