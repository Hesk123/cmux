// Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT rows 117, 118, D-4, D-5).
//
// THE one place in this build that decides where Claude Code's data is read from.
//
// Why a single provider (row 118). A probe on this Mac proved both Swift
// home-directory APIs ignore a HOME override, so the temp-HOME test seam the harness
// originally specified does not work at all -- H3 has no way to point the UI at a
// fixture unless the app itself offers a seam. This type is that seam, and
// CMUX_CAROUSEL_DATA_ROOT is the override. `CMUX_AGENT_JOURNAL_PATH` in
// AgentJournalLifecycleCenter is the house precedent for exactly this shape.
//
// Why the home APIs are banned everywhere else. Sources/ holds ~109 uses of
// FileManager.default.homeDirectoryForCurrentUser and NSHomeDirectory(), and one of
// them is SidebarPathFormatter.homeDirectoryPath -- a `static let` a new file can read
// in one expression, containing neither banned name. Reusing an existing helper is the
// LIKELY path, not the unlucky one, so the ban covers helpers and not just API names.
// scripts/carousel-gates/data-root-seam-check.sh enforces it over the whole diff and
// allowlists exactly this file, because a ban with nowhere legitimate to resolve a
// default is a ban that gets worked around rather than followed.
//
// Where the data actually is (D-4). Every Claude Code session Dawid runs is on the
// Hive inside tmux; this Mac's ~/.claude/sessions is empty. The real root is the
// Hive's ~/.claude, pulled over the existing ssh channel into a local mirror by
// tools/carousel-mirror/pull-claude-data.sh. The local Mac root is the fallback for a
// session that genuinely runs here, or for a mirror that has never run.
//
// Staleness is part of the value, not a detail (17.3). A mirror can be stale for
// reasons the app cannot see -- bridge down, Hive asleep, a partial rsync -- and a
// carousel that silently shows five-minute-old sessions as live is worse than one
// that says it is stale. `freshness` makes that renderable, and `Freshness.stale`
// is distinct from an empty root so "correctly empty" and "structurally blind" can
// never be confused (row 85).

import Foundation

/// Where the carousel reads Claude Code session, sub-agent and statusline data from.
struct CarouselDataRoot: Sendable, Equatable {
    /// How this root was chosen. Surfaced in the UI's degraded states so a user is
    /// told which host they are looking at rather than shown an unexplained blank.
    enum Source: String, Sendable {
        /// `CMUX_CAROUSEL_DATA_ROOT`. Used by H3 fixtures and by nothing that ships.
        case environmentOverride
        /// An explicit path set in cmux's settings.
        case setting
        /// The local mirror of the Hive's `~/.claude`, refreshed by the row-117 bridge.
        case mirror
        /// This Mac's own `~/.claude`, for a session genuinely running here.
        case localFallback
    }

    enum Freshness: Sendable, Equatable {
        /// Refreshed within the row-91 window.
        case fresh(age: TimeInterval)
        /// Older than the window. The UI renders its stale state; it does not guess.
        case stale(age: TimeInterval, host: String?)
        /// No stamp at all: the mirror has never run, or this is a local root.
        case unknown
    }

    let url: URL
    let source: Source
    let freshness: Freshness

    /// The mirror's staleness bound (row 91, D-4). The statusline snapshot carries its
    /// own, longer bound at row 76; the two are different clocks and are not merged.
    static let mirrorMaxAge: TimeInterval = 5

    // MARK: - Sub-paths
    // Named here so no call site builds a path by string interpolation, which is how
    // a read ends up outside the seam without any banned API appearing anywhere.

    var sessionsDirectory: URL { url.appending(path: "sessions") }
    var projectsDirectory: URL { url.appending(path: "projects") }
    var statuslineSnapshotsDirectory: URL { url.appending(path: "statusline-snapshots") }

    func subAgentsDirectory(projectSlug: String, sessionID: String) -> URL {
        projectsDirectory
            .appending(path: projectSlug)
            .appending(path: sessionID)
            .appending(path: "subagents")
    }

    // MARK: - Resolution

    /// Resolution order: environment override, then an explicit setting, then the
    /// mirror if it has ever run, then this Mac's own `~/.claude`.
    ///
    /// - Parameters:
    ///   - environment: injected so tests do not have to mutate the real process
    ///     environment, which would race every other test in the same process.
    ///   - settingPath: an explicit path from cmux settings, if one is configured.
    ///   - fileManager: injected for the same reason.
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        settingPath: String? = nil,
                        fileManager: FileManager = .default,
                        now: Date = .now) -> CarouselDataRoot {
        if let raw = environment["CMUX_CAROUSEL_DATA_ROOT"], !raw.isEmpty {
            let url = URL(fileURLWithPath: raw, isDirectory: true)
            return CarouselDataRoot(url: url, source: .environmentOverride,
                                    freshness: .unknown)
        }
        if let settingPath, !settingPath.isEmpty {
            let url = URL(fileURLWithPath: settingPath, isDirectory: true)
            return CarouselDataRoot(url: url, source: .setting, freshness: .unknown)
        }
        let mirror = mirrorURL(fileManager: fileManager)
        if fileManager.fileExists(atPath: mirror.path(percentEncoded: false)) {
            return CarouselDataRoot(url: mirror, source: .mirror,
                                    freshness: mirrorFreshness(at: mirror, now: now))
        }
        return CarouselDataRoot(url: localFallbackURL(fileManager: fileManager),
                                source: .localFallback, freshness: .unknown)
    }

    /// The mirror lives under Application Support, which resolves without touching a
    /// home-directory API at all.
    static func mirrorURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appending(path: "cmux").appending(path: "carousel-claude-mirror")
    }

    /// This Mac's own `~/.claude`.
    ///
    /// The ONLY sanctioned use of a home-directory API in this build, allowlisted by
    /// name in scripts/carousel-gates/data-root-seam-check.sh. Every other read goes
    /// through a `CarouselDataRoot`, so a fixture pointed at a crafted root cannot be
    /// silently bypassed by a call site that resolved home for itself.
    static func localFallbackURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser.appending(path: ".claude")
    }

    /// Reads the stamp the mirror writes at the end of each successful pull.
    ///
    /// The stamp is written last, after the data lands, so a stamp can never be newer
    /// than the data it vouches for. A half-finished pull leaves the previous stamp,
    /// which reads as stale rather than as fresh-but-truncated.
    static func mirrorFreshness(at url: URL, now: Date = .now) -> Freshness {
        let stampURL = url.appending(path: ".mirror-stamp")
        guard let data = try? Data(contentsOf: stampURL),
              let text = String(data: data, encoding: .utf8) else {
            return .unknown
        }
        var epoch: TimeInterval?
        var host: String?
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "completed_epoch": epoch = TimeInterval(parts[1])
            case "host": host = String(parts[1])
            default: break
            }
        }
        guard let epoch else { return .unknown }
        let age = now.timeIntervalSince1970 - epoch
        return age <= mirrorMaxAge ? .fresh(age: age) : .stale(age: age, host: host)
    }
}
