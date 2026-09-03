// GPL-3.0-or-later modified-file notice (CONTRACT row 129):
// Modified 2026-09-02 for the cmux carousel UI (unit U1: track geometry, card shell,
// session data source, live/snapshot swap, and the window-scoped mode seam).

import AppKit
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The data half of U1: what a card *is*, where its facts come from, and what it
/// says when it cannot get them. CONTRACT rows 43, 85, 91, 117, 118, 124, 126 and
/// rulings D-4, D-5.
@MainActor
@Suite("Carousel session data")
struct CarouselSessionMatchingTests {
    private func makeRecord(
        sessionId: String = "s1",
        name: String? = nil,
        status: String? = "idle",
        tmux: String? = nil,
        cwd: String = "/home/dawid"
    ) throws -> CarouselClaudeSessionRecord {
        var fields: [String] = [
            "\"sessionId\":\"\(sessionId)\"",
            "\"cwd\":\"\(cwd)\"",
        ]
        if let name { fields.append("\"name\":\"\(name)\"") }
        if let status { fields.append("\"status\":\"\(status)\"") }
        if let tmux { fields.append("\"tmux\":\"\(tmux)\"") }
        let json = "{\(fields.joined(separator: ","))}"
        return try JSONDecoder().decode(
            CarouselClaudeSessionRecord.self,
            from: Data(json.utf8)
        )
    }

    // MARK: - Record parsing

    @Test("A live session file parses, including the tmux target's two components")
    func recordParsing() throws {
        // Shape taken verbatim from a real file on the Hive root, not invented.
        let record = try makeRecord(
            sessionId: "32999e8f-c459-4e76-aed9-4f4b6e48df79",
            name: "dawid-b2",
            status: "busy",
            tmux: "hive-claude:@10.%10"
        )
        #expect(record.tmuxPaneId == "%10")
        #expect(record.tmuxSessionName == "hive-claude")
        #expect(record.carouselStatus == .busy)
        #expect(record.projectSlug == "-home-dawid")
    }

    @Test("Unknown fields do not break decoding")
    func recordToleratesUnknownFields() throws {
        let json = """
        {"sessionId":"s1","cwd":"/home/dawid","somethingClaudeAddsLater":42}
        """
        let record = try JSONDecoder().decode(
            CarouselClaudeSessionRecord.self,
            from: Data(json.utf8)
        )
        // A carousel that stops reading the directory because one key moved is
        // worse than one that ignores what it does not know.
        #expect(record.sessionId == "s1")
        #expect(record.tmuxPaneId == nil)
    }

    @Test("A malformed tmux target yields nil rather than a wrong pane id")
    func malformedTmuxTarget() throws {
        #expect(try makeRecord(tmux: "hive-claude").tmuxPaneId == nil)
        #expect(try makeRecord(tmux: "hive-claude:@10.").tmuxPaneId == nil)
        #expect(try makeRecord(tmux: "").tmuxSessionName == nil)
    }

    // MARK: - Matching (D-4)

    @Test("D-4: the tmux pane id is an exact match and takes precedence")
    func matchesByPaneId() throws {
        let records = [
            try makeRecord(sessionId: "a", name: "dawid-10", tmux: "hive-brand:@11.%11"),
            try makeRecord(sessionId: "b", name: "dawid-b2", tmux: "hive-claude:@10.%10"),
        ]
        let hit = CarouselSessionMatcher.match(
            surface: CarouselSurfaceIdentity(tmuxPaneId: "%10", launchCommand: nil, title: nil, directory: nil),
            against: records
        )
        #expect(hit?.sessionId == "b")
    }

    @Test("D-4: an unambiguous tmux session name in the launch command matches")
    func matchesBySessionName() throws {
        let records = [
            try makeRecord(sessionId: "a", tmux: "hive-brand:@11.%11"),
            try makeRecord(sessionId: "b", tmux: "hive-claude:@10.%10"),
        ]
        let hit = CarouselSessionMatcher.match(
            surface: CarouselSurfaceIdentity(
                tmuxPaneId: nil,
                launchCommand: "initialCommand:ssh hive -t tmux attach -t hive-claude",
                title: nil,
                directory: nil
            ),
            against: records
        )
        #expect(hit?.sessionId == "b")
    }

    @Test("An ambiguous match returns nil rather than picking one")
    func ambiguousMatchIsNoMatch() throws {
        // Two sessions inside the same tmux session both match the command. Picking
        // one would be a coin flip, and a wrong match puts a card's status pill and
        // its sub-agent list on someone else's session - worse than no match, which
        // row 126 already defines a rendering for.
        let records = [
            try makeRecord(sessionId: "a", tmux: "hive-claude:@10.%10"),
            try makeRecord(sessionId: "b", tmux: "hive-claude:@11.%11"),
        ]
        let hit = CarouselSessionMatcher.match(
            surface: CarouselSurfaceIdentity(
                tmuxPaneId: nil,
                launchCommand: "tmuxStartCommand:tmux attach -t hive-claude",
                title: nil,
                directory: nil
            ),
            against: records
        )
        #expect(hit == nil)
    }

    @Test("A shared working directory never produces a match")
    func directoryIsNotASignal() throws {
        // Every session observed on the live root reports the same cwd, so a cwd
        // rung would turn "no match" into a confident wrong match on every card.
        let records = [
            try makeRecord(sessionId: "a", cwd: "/home/dawid"),
            try makeRecord(sessionId: "b", cwd: "/home/dawid"),
        ]
        let hit = CarouselSessionMatcher.match(
            surface: CarouselSurfaceIdentity(
                tmuxPaneId: nil,
                launchCommand: nil,
                title: nil,
                directory: "/home/dawid"
            ),
            against: records
        )
        #expect(hit == nil)
    }

    // MARK: - Data root (row 118 / D-5)

    @Test("Row 118: the environment override wins over the settings key")
    func environmentOverrideWins() {
        let defaults = UserDefaults(suiteName: "carousel.tests.\(UUID().uuidString)")!
        defaults.set("/from/settings", forKey: CarouselDataRoot.settingsKey)
        let root = CarouselDataRoot(
            environment: [CarouselDataRoot.environmentKey: "/from/env"],
            defaults: defaults
        )
        #expect(root.url.path(percentEncoded: false).hasPrefix("/from/env"))
    }

    @Test("Row 118: the settings key wins over the mirror default")
    func settingsKeyWins() {
        let defaults = UserDefaults(suiteName: "carousel.tests.\(UUID().uuidString)")!
        defaults.set("/from/settings", forKey: CarouselDataRoot.settingsKey)
        let root = CarouselDataRoot(environment: [:], defaults: defaults)
        #expect(root.url.path(percentEncoded: false).hasPrefix("/from/settings"))
    }

    @Test("Row 118: an empty override is ignored rather than resolving to /")
    func emptyOverrideIsIgnored() {
        let defaults = UserDefaults(suiteName: "carousel.tests.\(UUID().uuidString)")!
        let root = CarouselDataRoot(
            environment: [CarouselDataRoot.environmentKey: "   "],
            defaults: defaults
        )
        #expect(root.url == CarouselDataRoot.defaultMirrorURL)
    }

    @Test("Row 118 positive control: the reader sees the injected root's own session")
    func injectedRootIsRead() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "carousel-root-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sessions = directory.appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // The fixture carries a canary the UI must display, not merely a count, so a
        // fixture that failed to bite is visible.
        let canary = "CANARY-\(UUID().uuidString.prefix(8))"
        let json = """
        {"sessionId":"fixture","cwd":"/tmp/fixture","name":"\(canary)","status":"busy","tmux":"fx:@1.%1"}
        """
        try Data(json.utf8).write(to: sessions.appending(path: "1.json", directoryHint: .notDirectory))

        let liveness = CarouselSessionLiveness(root: CarouselDataRoot(url: directory))
        let records = liveness.records()
        #expect(records.count == 1)
        #expect(records.first?.name == canary)
    }

    @Test("Row 118 negative control: an empty root shows nothing, not the real sessions")
    func emptyRootShowsNothing() throws {
        // A provider that silently falls back to the real Hive root would pass the
        // positive control above and fail nothing without this.
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "carousel-empty-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory.appending(path: "sessions", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let liveness = CarouselSessionLiveness(root: CarouselDataRoot(url: directory))
        #expect(liveness.records().isEmpty)
    }

    // MARK: - Row 91: the cache window

    @Test("Row 91: a read inside the 2 s window is served from cache")
    func cacheWindow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "carousel-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sessions = directory.appending(path: "sessions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let liveness = CarouselSessionLiveness(root: CarouselDataRoot(url: directory))
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(liveness.records(now: start).isEmpty)

        try Data(#"{"sessionId":"late","cwd":"/tmp"}"#.utf8)
            .write(to: sessions.appending(path: "1.json", directoryHint: .notDirectory))

        // Still inside the window: the new file is deliberately not visible yet.
        #expect(liveness.records(now: start.addingTimeInterval(1)).isEmpty)
        // Past it: it is.
        #expect(liveness.records(now: start.addingTimeInterval(2.5)).count == 1)
    }

    @Test("Row 117: a mirror older than the staleness bound is not fresh")
    func stalenessBound() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "carousel-stale-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let root = CarouselDataRoot(url: directory)
        #expect(root.isFresh())
        // A downed ssh bridge must read as stale rather than as an idle machine.
        let later = Date().addingTimeInterval(CarouselDataRoot.stalenessBound + 5)
        #expect(!root.isFresh(now: later))
        #expect((root.age(now: later) ?? 0) > CarouselDataRoot.stalenessBound)
    }

    @Test("A missing root has no age and is never fresh")
    func missingRoot() {
        let root = CarouselDataRoot(url: URL(filePath: "/nonexistent/carousel/root"))
        #expect(root.age() == nil)
        #expect(!root.isFresh())
    }

    // MARK: - Row 10: the never-captured flank renders the placeholder

    private func makeSession(
        name: String = "session",
        lastActivity: Date? = nil
    ) -> CarouselSession {
        CarouselSession(
            panelId: UUID(),
            workspaceId: UUID(),
            resourceId: "local/terminal/\(UUID().uuidString)",
            claudeSessionId: "s1",
            projectSlug: "-tmp-fixture",
            displayName: name,
            subtitle: "/tmp/fixture",
            status: .idle,
            isClaudeCodeSurface: true,
            lastActivity: lastActivity
        )
    }

    @Test("Row 10: a card with no capture shows the placeholder, not a blank body")
    func placeholderWhenNoCapture() {
        // Only the centred session has a live libghostty view, and Ghostty pauses a
        // surface that is not visible, so a session never centred in this app run
        // has no pixels to snapshot. The ruling is that it renders its own name, cwd
        // and last activity - never a black rectangle.
        let body = CarouselCardBodyView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        #expect(!body.hasSnapshot)
        #expect(!body.showsPlaceholder)

        body.setPlaceholder(makeSession(name: "never-visited"))
        #expect(body.showsPlaceholder)
        #expect(!body.hasSnapshot)
    }

    @Test("Row 10: a real capture replaces the placeholder")
    func captureReplacesPlaceholder() {
        let body = CarouselCardBodyView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        body.setPlaceholder(makeSession(name: "never-visited"))
        #expect(body.showsPlaceholder)

        // Passing nil is how the swap coordinator retires the placeholder the moment
        // a capture exists for that session; a placeholder that survived a real
        // capture would sit over live content.
        body.setPlaceholder(nil)
        #expect(!body.showsPlaceholder)
    }

    @Test("Row 85: the placeholder states an unknown last activity rather than inventing one")
    func placeholderDistinguishesUnknownActivity() {
        // "Unknown" and "a long time ago" are different facts. A live Hive session
        // was observed with an `updatedAt` 6.7 days old and a running pid, so an age
        // is never evidence of death and must not be rendered as though it were.
        let unknown = CarouselCardPlaceholderView(session: makeSession(lastActivity: nil))
        let known = CarouselCardPlaceholderView(session: makeSession(lastActivity: Date(timeIntervalSince1970: 1_788_000_000)))
        #expect(unknown.lastActivityText != known.lastActivityText)
        #expect(unknown.lastActivityText.contains("Not opened"))
        #expect(known.lastActivityText.contains("Last activity"))
    }

    @Test("Row 115: a fresh mount has no live view attached")
    func freshMountHasNoLiveView() {
        // The zero state of row 115's seam. The one-state needs a live
        // libghostty panel and is proven on the running app, not here.
        #expect(CarouselPaneMount().attachedLiveViewCount == 0)
    }

    @Test("Row 27: the card corner is circular, not the squircle default")
    func cardCornerIsCircular() {
        let card = CarouselCardView(metrics: CarouselMetrics(viewport: CGSize(width: 1344, height: 1080)))
        card.layout()
        #expect(card.layer?.cornerCurve == .circular)
    }

    // MARK: - The U5 compatibility init

    @Test("U5's six-argument shape still compiles and takes honest unknown values")
    func compatibilityInit() {
        let session = CarouselSession(
            panelId: UUID(),
            resourceId: "local/terminal/x",
            claudeSessionId: nil,
            projectSlug: nil,
            displayName: "n",
            subtitle: "s"
        )
        // The four fields U5's transcription lacks must not be guessed into
        // something that reads as a claim: no workspace, no session state,
        // and not Claude Code. A fabricated `workspaceId` breaks panel lookup
        // and value semantics, so nil is asserted, not just the honest three.
        #expect(session.workspaceId == nil)
        #expect(session.status == .outOfScope)
        #expect(!session.isClaudeCodeSurface)
        #expect(session.lastActivity == nil)
    }
}
