// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Added 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import Foundation

/// One `<root>/sessions/<pid>.json` file: Claude Code's own record of a running
/// session. Decoded leniently - a future Claude Code adds fields, and a carousel
/// that stops reading the directory because one key moved is worse than one that
/// ignores what it does not know.
struct CarouselClaudeSessionRecord: Decodable, Equatable, Sendable {
    let sessionId: String
    let cwd: String
    /// The session's display name, as Claude Code derived or was given it.
    let name: String?
    /// `busy` or `idle` in every sample observed on the live Hive root.
    let status: String?
    /// Milliseconds since epoch.
    let updatedAt: Double?
    /// tmux target in `<session>:@<window>.%<pane>` form.
    let tmux: String?

    /// The `%pane` component, which is unique per tmux server and is the strongest
    /// signal available for mapping a cmux surface to a session (D-4).
    var tmuxPaneId: String? {
        guard let tmux, let range = tmux.range(of: ".%", options: .backwards) else { return nil }
        let pane = String(tmux[range.lowerBound...].dropFirst())
        return pane.count > 1 ? pane : nil
    }

    /// The tmux session name, i.e. the part before the colon.
    var tmuxSessionName: String? {
        guard let tmux, let separator = tmux.firstIndex(of: ":") else { return nil }
        let session = String(tmux[tmux.startIndex..<separator])
        return session.isEmpty ? nil : session
    }

    /// Claude Code's transcript directory name: the cwd with `/` replaced by `-`.
    var projectSlug: String {
        cwd.replacing("/", with: "-")
    }

    var carouselStatus: CarouselSessionStatus {
        status == "busy" ? .busy : .idle
    }

    /// `updatedAt` is milliseconds since epoch. Only used for display on the
    /// placeholder card - **never** as a liveness bound. A live Hive session was
    /// observed with an `updatedAt` 6.7 days old and a running pid, so an age
    /// bound would report a healthy long-lived session as dead (U5-D8).
    var lastActivity: Date? {
        guard let updatedAt, updatedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: updatedAt / 1000)
    }
}

/// Reads the mirrored `sessions/` directory and answers, for one cmux surface,
/// which Claude Code session it is (CONTRACT rows 43, 91, 105, 117, 126).
///
/// Row 91 bounds the cache at N = 2 s. That bound is **local**: it is how long this
/// reader may serve a cached answer after the directory changed on disk. The
/// end-to-end figure is larger - D-4 pulls Hive's `~/.claude` every <= 5 s, so a
/// session starting on Hive can take up to 5 s plus this window to appear here.
/// The two numbers are kept apart deliberately; conflating them would let a test
/// assert 2 s and a Phase 6 report claim it end to end.
@MainActor
final class CarouselSessionLiveness {
    /// Row 91.
    static let cacheWindow: TimeInterval = 2

    private let root: CarouselDataRoot
    private let fileManager: FileManager
    private var cachedRecords: [CarouselClaudeSessionRecord] = []
    private var cachedAt: Date?

    init(root: CarouselDataRoot, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
    }

    /// Every session the mirror currently reports, cached for
    /// ``cacheWindow``.
    func records(now: Date = .now) -> [CarouselClaudeSessionRecord] {
        if let cachedAt, now.timeIntervalSince(cachedAt) < Self.cacheWindow {
            return cachedRecords
        }
        cachedRecords = Self.readRecords(in: root, fileManager: fileManager)
        cachedAt = now
        return cachedRecords
    }

    /// Drops the cache. Used when the data root changes under the app, and by
    /// tests that need to observe a directory write without waiting 2 s.
    func invalidate() {
        cachedAt = nil
        cachedRecords = []
    }

    /// The freshness of the mirror itself, which is a different question from
    /// whether any session file parsed. Row 117: bridge down, Hive asleep and a
    /// half-finished copy all leave a root that reads fine and lies.
    func isMirrorFresh(now: Date = .now) -> Bool {
        root.isFresh(now: now, fileManager: fileManager)
    }

    func mirrorAge(now: Date = .now) -> TimeInterval? {
        root.age(now: now, fileManager: fileManager)
    }

    private static func readRecords(
        in root: CarouselDataRoot,
        fileManager: FileManager
    ) -> [CarouselClaudeSessionRecord] {
        guard let names = try? fileManager.contentsOfDirectory(
            atPath: root.sessionsURL.path(percentEncoded: false)
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        return names
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .compactMap { name in
                let url = root.sessionsURL.appending(path: name, directoryHint: .notDirectory)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(CarouselClaudeSessionRecord.self, from: data)
            }
    }
}

/// What a cmux surface knows about itself that could identify a Claude session.
/// A value type so the matcher below is pure and testable without a live app.
struct CarouselSurfaceIdentity: Equatable, Sendable {
    /// tmux's own pane id for the surface's active pane, e.g. `%10`, when cmux's
    /// tmux integration reported one.
    var tmuxPaneId: String?
    /// The command the surface was started with. For a Hive session this carries
    /// the tmux session name, as an `ssh ... tmux attach -t <session>` invocation.
    var launchCommand: String?
    /// The surface's window title, which Claude Code sets to its session name.
    var title: String?
    /// The surface's working directory.
    var directory: String?
}

/// Maps a cmux surface to a Claude Code session record (D-4).
///
/// The precedence below runs strongest-signal first and stops at the first hit.
/// Each rung is deliberately narrow: a wrong match puts a card's status pill and
/// its sub-agent list on someone else's session, which is worse than no match at
/// all, and row 126 already defines what an unmatched agent surface renders.
enum CarouselSessionMatcher {
    static func match(
        surface: CarouselSurfaceIdentity,
        against records: [CarouselClaudeSessionRecord]
    ) -> CarouselClaudeSessionRecord? {
        // 1. tmux pane id. Unique per tmux server, and every session in scope lives
        //    on the one Hive server, so this is exact when it is available.
        if let paneId = surface.tmuxPaneId,
           let hit = records.first(where: { $0.tmuxPaneId == paneId }) {
            return hit
        }
        // 2. tmux session name inside the launch command. Exact when the surface
        //    attaches a named session, which is how the Hive sessions are started.
        if let command = surface.launchCommand {
            let named = records.filter { record in
                guard let session = record.tmuxSessionName else { return false }
                return command.contains(session)
            }
            // Only accept an unambiguous hit: two sessions in the same tmux session
            // would both match and picking one would be a coin flip.
            if named.count == 1 { return named[0] }
        }
        // 3. Session name in the surface title. Claude Code writes its own name
        //    there, so this survives an attach cmux never saw.
        if let title = surface.title {
            let named = records.filter { record in
                guard let name = record.name, !name.isEmpty else { return false }
                return title.contains(name)
            }
            if named.count == 1 { return named[0] }
        }
        // Working directory is deliberately NOT a rung. Every observed session on
        // the live root reports the same cwd, so it identifies nothing and would
        // turn "no match" into a confident wrong match.
        return nil
    }
}
