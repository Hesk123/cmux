// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

/// CONTRACT rows 11, 71, 127 and 132 — the sub-agents data layer.
///
/// Every fixture carries a canary the assertion names, rather than only a
/// count, so a fixture that failed to bite is visible instead of passing
/// vacuously.
@Suite struct CarouselSubAgentsTests {

    // MARK: - Fixture

    /// Builds a data root on disk with a real `projects/<slug>/<id>/subagents`
    /// tree, so the tests exercise path derivation, the glob and the parser
    /// exactly as the running app does.
    struct Fixture {
        let root: CarouselDataRoot
        let session: SubAgentsSessionKey
        let directory: URL

        static let projectSlug = "-home-dawid"
        static let sessionID = "fixture-session"

        init() throws {
            let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("cmux-carousel-u4-\(UUID().uuidString)", isDirectory: true)
            root = CarouselDataRoot(url: base, source: .environmentOverride, freshness: .unknown)
            guard let key = SubAgentsSessionKey(
                projectSlug: Self.projectSlug,
                sessionID: Self.sessionID
            ) else {
                throw FixtureError.invalidKey
            }
            session = key
            directory = root.subAgentsDirectory(
                projectSlug: Self.projectSlug,
                sessionID: Self.sessionID
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }

        enum FixtureError: Error { case invalidKey }

        func remove() {
            try? FileManager.default.removeItem(at: root.url)
        }

        /// Writes one agent: a transcript whose last line has the requested
        /// shape, a sibling metadata file, and a modification time.
        @discardableResult
        func writeAgent(
            id: String,
            name: String?,
            agentType: String,
            description: String,
            spawnDepth: Int,
            parentAgentId: String? = nil,
            lastLineIsFinalReport: Bool,
            modifiedAt: Date,
            writeMetadata: Bool = true,
            sessionID: String = Self.sessionID
        ) throws -> String {
            let dir: URL
            if sessionID == Self.sessionID {
                dir = directory
            } else {
                dir = root.subAgentsDirectory(projectSlug: Self.projectSlug, sessionID: sessionID)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let transcript = dir.appendingPathComponent("agent-\(id).jsonl")
            let finalLine = lastLineIsFinalReport
                ? #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}"#
                : #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}"#
            let body = [
                #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"go"}]}}"#,
                finalLine,
                "",
            ].joined(separator: "\n")
            try body.write(to: transcript, atomically: true, encoding: .utf8)

            if writeMetadata {
                var meta: [String: Any] = [
                    "agentType": agentType,
                    "description": description,
                    "spawnDepth": spawnDepth,
                ]
                if let name { meta["name"] = name }
                if let parentAgentId { meta["parentAgentId"] = parentAgentId }
                let data = try JSONSerialization.data(withJSONObject: meta)
                try data.write(to: dir.appendingPathComponent("agent-\(id).meta.json"))
            }

            try FileManager.default.setAttributes(
                [.modificationDate: modifiedAt],
                ofItemAtPath: transcript.path
            )
            return id
        }
    }

    private func scan(_ fixture: Fixture, now: Date = Date()) -> SubAgentScan {
        SubAgentDirectoryScanner.scan(
            root: fixture.root,
            session: fixture.session,
            now: now,
            policy: .default,
            cache: [:]
        ).scan
    }

    // MARK: - Counting and the glob (row 11, row 71)

    @Test("Zero agents reads as ready and empty, not as a missing session")
    func zeroAgents() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let result = scan(fixture)
        #expect(result.availability == .ready)
        #expect(result.records.isEmpty)
        #expect(result.runningCount == 0)
    }

    @Test("One running agent is counted once, not twice, despite its metadata sibling")
    func oneAgentCountedOnce() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "acanary-one",
            name: "canary-one",
            agentType: "general-purpose",
            description: "canary description",
            spawnDepth: 1,
            lastLineIsFinalReport: false,
            modifiedAt: now
        )
        let result = scan(fixture, now: now)
        // A bare `agent-*` glob would find two files for this one agent.
        #expect(result.records.count == 1)
        #expect(result.runningCount == 1)
        #expect(result.records.first?.displayTitle == "canary-one")
        #expect(result.records.first?.displaySubtitle == "canary description")
    }

    @Test("Three agents: only the running ones are counted, and every name is read")
    func threeAgentsCountRunningOnly() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "arunner", name: "canary-runner", agentType: "cmux-maker-U4",
            description: "still working", spawnDepth: 0,
            lastLineIsFinalReport: false, modifiedAt: now
        )
        try fixture.writeAgent(
            id: "afinished", name: "canary-finished", agentType: "gemini-researcher",
            description: "wrapped up", spawnDepth: 1,
            lastLineIsFinalReport: true, modifiedAt: now.addingTimeInterval(-30)
        )
        try fixture.writeAgent(
            id: "anested", name: nil, agentType: "general-purpose",
            description: "nested child", spawnDepth: 2, parentAgentId: "arunner",
            lastLineIsFinalReport: false, modifiedAt: now.addingTimeInterval(-1)
        )

        let result = scan(fixture, now: now)
        #expect(result.records.count == 3)
        // The directory is a history, not a roster: the finished agent is
        // listed and not counted.
        #expect(result.runningCount == 2)

        let titles = Set(result.records.map(\.displayTitle))
        #expect(titles == ["canary-runner", "canary-finished", "general-purpose"])

        let finished = result.records.first { $0.id == "afinished" }
        #expect(finished?.activity == .finished)
        let nested = result.records.first { $0.id == "anested" }
        #expect(nested?.parentAgentID == "arunner")
        #expect(nested?.spawnDepth == 2)
    }

    @Test("Forty agents scan and count correctly")
    func fortyAgents() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        for index in 0..<40 {
            try fixture.writeAgent(
                id: String(format: "a%02d", index),
                name: "canary-\(index)",
                agentType: "general-purpose",
                description: "task \(index)",
                spawnDepth: 1,
                lastLineIsFinalReport: index % 2 == 0,
                // Past BOTH boundaries with margin: terminal shapes settle at
                // 2 s, the running bound is 120 s. Offsets 0..<40 straddle the
                // settle window (index 0 reads running); even +1 leaves index
                // 0 at ~1 s, still inside it. 30..69 is finished-or-running
                // exactly as the comment below states, on every run.
                modifiedAt: now.addingTimeInterval(-Double(30 + index))
            )
        }
        let result = scan(fixture, now: now)
        #expect(result.records.count == 40)
        // Even indices ended on a final report and settled (all past the
        // 2 s window); odd ones are mid tool call (all inside 120 s).
        #expect(result.runningCount == 20)
        #expect(result.records.contains { $0.displayTitle == "canary-39" })
    }

    @Test("Scanning session A never lists session B's agents")
    func twoSessionsAreIsolated() throws {
        // The store re-points as the carousel scrolls; a widened glob or a
        // recursive enumerator would bleed one session's agents into
        // another's panel and pass every single-session test above.
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "a-one", name: "canary-a", agentType: "general-purpose",
            description: "session A agent", spawnDepth: 0,
            lastLineIsFinalReport: false, modifiedAt: now
        )
        try fixture.writeAgent(
            id: "b-one", name: "canary-b", agentType: "general-purpose",
            description: "session B agent", spawnDepth: 0,
            lastLineIsFinalReport: false, modifiedAt: now,
            sessionID: "other-session"
        )
        let result = scan(fixture, now: now)
        #expect(result.records.count == 1)
        #expect(result.records.first?.id == "a-one")
        #expect(!result.records.map(\.id).contains("b-one"))
    }

    // MARK: - Display-name fallback (row 11)

    @Test("A missing metadata file falls back to the agent id, and says so")
    func metadataFallback() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "adeadbeefcafe1234", name: nil, agentType: "unused",
            description: "unused", spawnDepth: 0,
            lastLineIsFinalReport: false, modifiedAt: now, writeMetadata: false
        )
        let record = try #require(scan(fixture, now: now).records.first)
        #expect(record.hasMetadata == false)
        #expect(record.displayTitle == "Agent " + String("adeadbeefcafe1234".suffix(8)))
        #expect(record.displaySubtitle == "Metadata not written yet")
    }

    @Test("agentType is the title when the agent has no name")
    func agentTypeIsTitleWithoutName() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "anoname", name: nil, agentType: "canary-agent-type",
            description: "d", spawnDepth: 1,
            lastLineIsFinalReport: false, modifiedAt: now
        )
        #expect(scan(fixture, now: now).records.first?.displayTitle == "canary-agent-type")
    }

    // MARK: - Liveness (row 127)

    @Test("A quiet transcript past the max age reads unknown, never idle")
    func staleReadsUnknown() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "astale", name: "canary-stale", agentType: "general-purpose",
            description: "blocked in a long tool call", spawnDepth: 1,
            lastLineIsFinalReport: false,
            modifiedAt: now.addingTimeInterval(-SubAgentLivenessPolicy.default.runningMaxAge - 1)
        )
        let result = scan(fixture, now: now)
        #expect(result.records.first?.activity == .unknown)
        #expect(result.runningCount == 0)
    }

    @Test("A final report inside the settle window is still counted as running")
    func settleWindowKeepsRunning() {
        let policy = SubAgentLivenessPolicy.default
        let now = Date()
        #expect(
            policy.activity(
                shape: .terminalAssistantText,
                modifiedAt: now.addingTimeInterval(-0.5),
                now: now
            ) == .running
        )
        #expect(
            policy.activity(
                shape: .terminalAssistantText,
                modifiedAt: now.addingTimeInterval(-5),
                now: now
            ) == .finished
        )
    }

    @Test("A transcript ending in a tool call is working, not finished")
    func toolUseIsWorking() {
        let toolUse = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"},{"type":"tool_use","name":"Bash"}]}}"#
        let text = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}"#
        let thinking = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"thinking"}]}}"#
        let user = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result"}]}}"#

        #expect(SubAgentTranscriptProbe.shape(inTail: Data("\(toolUse)\n".utf8)) == .working)
        #expect(SubAgentTranscriptProbe.shape(inTail: Data("\(text)\n".utf8)) == .terminalAssistantText)
        #expect(SubAgentTranscriptProbe.shape(inTail: Data("\(thinking)\n".utf8)) == .working)
        #expect(SubAgentTranscriptProbe.shape(inTail: Data("\(user)\n".utf8)) == .working)
    }

    @Test("A half-written trailing line is skipped for the last complete one")
    func partialTrailingLineIgnored() {
        let complete = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}"#
        let partial = #"{"type":"assistant","message":{"role":"assist"#
        let tail = Data("\(complete)\n\(partial)".utf8)
        #expect(SubAgentTranscriptProbe.shape(inTail: tail) == .terminalAssistantText)
    }

    // MARK: - Nesting (row 11)

    @Test("Children are drawn under their parent, and an orphan still appears")
    func outlineNesting() throws {
        let now = Date()
        let parent = SubAgentRecord(
            id: "parent", name: "canary-parent", agentType: "t", taskDescription: "d",
            model: nil, spawnDepth: 0, parentAgentID: nil,
            activity: .running, lastActivity: now, hasMetadata: true
        )
        let child = SubAgentRecord(
            id: "child", name: "canary-child", agentType: "t", taskDescription: "d",
            model: nil, spawnDepth: 1, parentAgentID: "parent",
            activity: .running, lastActivity: now.addingTimeInterval(-1), hasMetadata: true
        )
        let grandchild = SubAgentRecord(
            id: "grandchild", name: "canary-grandchild", agentType: "t", taskDescription: "d",
            model: nil, spawnDepth: 2, parentAgentID: "child",
            activity: .running, lastActivity: now.addingTimeInterval(-2), hasMetadata: true
        )
        // Its parent's transcript has aged out of the directory.
        let orphan = SubAgentRecord(
            id: "orphan", name: "canary-orphan", agentType: "t", taskDescription: "d",
            model: nil, spawnDepth: 2, parentAgentID: "gone",
            activity: .running, lastActivity: now.addingTimeInterval(-3), hasMetadata: true
        )

        let rows = SubAgentOutline.rows(for: [grandchild, orphan, child, parent])
        #expect(rows.map(\.id) == ["parent", "child", "grandchild", "orphan"])
        #expect(rows.map(\.depth) == [0, 1, 2, 0])
    }

    @Test("A cycle in the parent links cannot hang the outline")
    func outlineCycleIsSafe() {
        let now = Date()
        let a = SubAgentRecord(
            id: "a", name: "a", agentType: "t", taskDescription: "d", model: nil,
            spawnDepth: 1, parentAgentID: "b", activity: .running,
            lastActivity: now, hasMetadata: true
        )
        let b = SubAgentRecord(
            id: "b", name: "b", agentType: "t", taskDescription: "d", model: nil,
            spawnDepth: 1, parentAgentID: "a", activity: .running,
            lastActivity: now, hasMetadata: true
        )
        let rows = SubAgentOutline.rows(for: [a, b])
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.id)) == ["a", "b"])
    }

    // MARK: - Negative controls (rows 118, 124, 132)

    @Test("An override resolves verbatim and is never silently replaced")
    func overrideNeverFallsBack() throws {
        // Row 118's mandatory negative control, named here: it resolves
        // through `resolve(environment:)` — the seam silent fallback would
        // live in — and asserts the returned root IS the override, byte for
        // byte. A future "helpful" substitution (mirror, home directory,
        // settings default) fails the first assertion before any scan runs.
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cmux-carousel-override-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let root = CarouselDataRoot.resolve(environment: ["CMUX_CAROUSEL_DATA_ROOT": base.path])
        #expect(root.url == base)
        #expect(root.source == .environmentOverride)

        // And a missing override is still the override, not a fallback: the
        // scan must report the missing path, never somebody else's data.
        let absent = base.appendingPathComponent("absent", isDirectory: true)
        let absentRoot = CarouselDataRoot.resolve(environment: ["CMUX_CAROUSEL_DATA_ROOT": absent.path])
        #expect(absentRoot.url == absent)
        let key = try #require(SubAgentsSessionKey(projectSlug: "s", sessionID: "i"))
        let result = SubAgentDirectoryScanner.scan(
            root: absentRoot, session: key, now: Date(), policy: .default, cache: [:]
        ).scan
        #expect(result.availability == .rootMissing(absent.path))
    }

    @Test("An empty data root renders the empty state and shows no real session")
    func emptyRootShowsNothing() throws {
        // The control that proves the injected root is the only root read. If
        // resolution leaked to the real mirror, this directory's emptiness
        // would not be what the scan reports.
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cmux-carousel-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        // Resolved through the seam, not hand-constructed: a silent
        // fallback inside resolve() would surface here as the wrong url.
        let root = CarouselDataRoot.resolve(environment: ["CMUX_CAROUSEL_DATA_ROOT": base.path])
        #expect(root.url == base)
        let key = try #require(SubAgentsSessionKey(projectSlug: "-home-dawid", sessionID: "nope"))
        let result = SubAgentDirectoryScanner.scan(
            root: root, session: key, now: Date(), policy: .default, cache: [:]
        ).scan
        #expect(result.availability == .sessionMissing)
        #expect(result.records.isEmpty)
    }

    @Test("A missing root is reported as missing, not as an empty session")
    func missingRootIsNamed() throws {
        let missing = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        ).appendingPathComponent("cmux-carousel-absent-\(UUID().uuidString)", isDirectory: true)
        let root = CarouselDataRoot(url: missing, source: .environmentOverride, freshness: .unknown)
        let key = try #require(SubAgentsSessionKey(projectSlug: "s", sessionID: "i"))
        let result = SubAgentDirectoryScanner.scan(
            root: root, session: key, now: Date(), policy: .default, cache: [:]
        ).scan
        #expect(result.availability == .rootMissing(missing.path))
    }

    @Test("A non-Claude-Code surface renders the out-of-scope state")
    func outOfScopeSurface() {
        // cmux also hosts Codex and OpenCode surfaces and neither writes these
        // files, so the honest answer is a defined state, not a zero count.
        #expect(SubAgentsSessionKey(projectSlug: nil, sessionID: "abc") == nil)
        #expect(SubAgentsSessionKey(projectSlug: "slug", sessionID: nil) == nil)
        // Both values become path components, so traversal is refused rather
        // than rewritten into a directory nobody asked for.
        #expect(SubAgentsSessionKey(projectSlug: "..", sessionID: "abc") == nil)
        #expect(SubAgentsSessionKey(projectSlug: "slug", sessionID: "../../etc") == nil)
        #expect(SubAgentsSessionKey(projectSlug: "slug", sessionID: "") == nil)

        let root = CarouselDataRoot(
            url: URL(fileURLWithPath: "/tmp", isDirectory: true),
            source: .environmentOverride,
            freshness: .unknown
        )
        let result = SubAgentDirectoryScanner.scan(
            root: root, session: nil, now: Date(), policy: .default, cache: [:]
        ).scan
        #expect(result.availability == .outOfScope)
        #expect(result.runningCount == 0)
    }

    @Test("Sub-agent paths follow Claude Code's own layout under the injected root")
    func subAgentPathLayout() {
        // U5 owns CarouselDataRootTests; this asserts only the one path helper
        // U4 depends on, so the two suites do not overlap.
        let root = CarouselDataRoot(
            url: URL(fileURLWithPath: "/tmp/root", isDirectory: true),
            source: .environmentOverride,
            freshness: .unknown
        )
        let url = root.subAgentsDirectory(projectSlug: "-home-dawid", sessionID: "abc")
        #expect(url.path(percentEncoded: false) == "/tmp/root/projects/-home-dawid/abc/subagents")
    }

    // MARK: - Mirror freshness (row 117)

    @Test("A stamp older than the mirror window reads stale and names its host")
    func staleStampIsNamed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stale = Int(Date().timeIntervalSince1970) - 600
        let stamp = "host=hive\ncompleted_epoch=\(stale)\n"
        try stamp.write(
            to: fixture.root.url.appending(path: ".mirror-stamp"),
            atomically: true,
            encoding: .utf8
        )
        let result = scan(fixture)
        guard case let .stale(_, host) = result.freshness else {
            Issue.record("expected a stale mirror, got \(result.freshness)")
            return
        }
        #expect(host == "hive")
    }

    @Test("A fresh stamp reads fresh, and no stamp reads unknown rather than stale")
    func freshAndUnknownStamps() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(scan(fixture).freshness == .unknown)

        let now = Int(Date().timeIntervalSince1970)
        try "host=hive\ncompleted_epoch=\(now)\n".write(
            to: fixture.root.url.appending(path: ".mirror-stamp"),
            atomically: true,
            encoding: .utf8
        )
        guard case .fresh = scan(fixture).freshness else {
            Issue.record("expected a fresh mirror")
            return
        }
    }

    // MARK: - Probe cache

    @Test("An unchanged transcript is served from the cache instead of re-read")
    func cacheAvoidsRereads() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeAgent(
            id: "acached", name: "canary-cached", agentType: "t", description: "d",
            spawnDepth: 1, lastLineIsFinalReport: false, modifiedAt: now
        )
        let first = SubAgentDirectoryScanner.scan(
            root: fixture.root, session: fixture.session, now: now, policy: .default, cache: [:]
        )
        #expect(first.cache["acached"]?.shape == .working)

        // Poison the cache entry. A second scan that reuses it proves the file
        // was not read again; a scan that re-read would disagree.
        let poisoned = [
            "acached": SubAgentTranscriptProbe.CacheEntry(
                modifiedAt: first.cache["acached"]!.modifiedAt,
                size: first.cache["acached"]!.size,
                shape: .terminalAssistantText
            )
        ]
        let second = SubAgentDirectoryScanner.scan(
            root: fixture.root, session: fixture.session,
            now: now.addingTimeInterval(10), policy: .default, cache: poisoned
        )
        #expect(second.scan.records.first?.activity == .finished)
    }
}
