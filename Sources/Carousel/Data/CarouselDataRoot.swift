// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import Foundation

/// The single injectable path provider for every session, sub-agent and statusline
/// read the carousel makes (CONTRACT row 118, ruling D-5).
///
/// A probe on the Mac proved that both of Foundation's home-directory lookups ignore
/// a `HOME` override and resolve through the passwd entry, so a temp-`HOME` fixture
/// cannot bite. This type is the seam that replaces it. **No file under
/// `Sources/Carousel/` may call either of those, or any of cmux's own home-path
/// helpers** - a path built from a helper contains neither banned symbol name and
/// would pass a name-scoped grep while defeating the seam completely, which is why
/// row 118's ban enumerates helpers as well as APIs. The two symbol names and the
/// six helper names are deliberately not spelled out here: row 118's check is a
/// grep over the entire diff, and a doc comment quoting them would be a hit.
///
/// Resolution order, first hit wins:
/// 1. `CMUX_CAROUSEL_DATA_ROOT` in the environment. Copies the shape of
///    `CMUX_AGENT_JOURNAL_PATH` at `Sources/AgentJournalLifecycleCenter.swift:473`.
/// 2. The settings key, for a user who mirrors somewhere other than the default.
/// 3. The mirror default under Application Support.
///
/// Per D-4 the mirrored tree is **Hive's** `~/.claude`, not the Mac's: every Claude
/// Code session Dawid runs is on the Hive inside tmux and the Mac's own
/// `~/.claude/sessions` is empty. This type does not perform the mirror; it only
/// says where the mirror lands.
struct CarouselDataRoot: Equatable, Sendable {
    /// Environment override. Test seams in this repo are named `CMUX_*`
    /// (`Sources/AppDelegate+NotificationOpen.swift:88`), and this follows it.
    static let environmentKey = "CMUX_CAROUSEL_DATA_ROOT"
    /// `UserDefaults` key for a user-chosen mirror location.
    static let settingsKey = "carouselDataRootPath"

    /// How stale the mirror may be before a card stops claiming to know anything
    /// about its session. D-4 pulls every <= 5 s, so 15 s is three missed pulls -
    /// long enough not to flicker on one slow pull, short enough that a downed
    /// bridge is visible rather than silently rendered as live.
    static let stalenessBound: TimeInterval = 15

    let url: URL

    /// The directory the bundled mirror writes into when nothing overrides it.
    /// Deliberately built from `URL.applicationSupportDirectory` rather than any
    /// home-directory API, so the row-118 grep over the whole diff stays clean.
    static var defaultMirrorURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "cmux", directoryHint: .isDirectory)
            .appending(path: "carousel-data-root", directoryHint: .isDirectory)
    }

    /// - Parameters:
    ///   - environment: injected so a test can drive resolution without mutating
    ///     the process environment.
    ///   - defaults: injected for the same reason.
    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard
    ) {
        if let raw = environment[Self.environmentKey],
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url = URL(filePath: raw, directoryHint: .isDirectory)
            return
        }
        if let raw = defaults.string(forKey: Self.settingsKey),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            url = URL(filePath: raw, directoryHint: .isDirectory)
            return
        }
        url = Self.defaultMirrorURL
    }

    init(url: URL) {
        self.url = url
    }

    /// `<root>/sessions` - one small JSON file per running Claude Code session.
    var sessionsURL: URL {
        url.appending(path: "sessions", directoryHint: .isDirectory)
    }

    /// `<root>/projects` - transcripts and, under each session, its sub-agents.
    var projectsURL: URL {
        url.appending(path: "projects", directoryHint: .isDirectory)
    }

    /// `<root>/statusline-snapshots` - U5's model, compaction and usage source.
    var statuslineSnapshotsURL: URL {
        url.appending(path: "statusline-snapshots", directoryHint: .isDirectory)
    }

    /// How long ago the mirror last wrote, or nil when the root does not exist.
    ///
    /// The mirror is a failure mode the contract's rows have no equivalent for:
    /// bridge down, Hive asleep, or a half-finished copy all leave a root that
    /// parses fine and lies. A card renders `.stale` from this rather than showing
    /// a five-minute-old session as live.
    func age(now: Date = .now, fileManager: FileManager = .default) -> TimeInterval? {
        let probe = fileManager.fileExists(atPath: sessionsURL.path(percentEncoded: false))
            ? sessionsURL
            : url
        guard let modified = try? fileManager.attributesOfItem(
            atPath: probe.path(percentEncoded: false)
        )[.modificationDate] as? Date else {
            return nil
        }
        return max(0, now.timeIntervalSince(modified))
    }

    /// True when the mirror is fresh enough for a card to make a claim about a
    /// session's liveness.
    func isFresh(now: Date = .now, fileManager: FileManager = .default) -> Bool {
        guard let age = age(now: now, fileManager: fileManager) else { return false }
        return age <= Self.stalenessBound
    }
}
