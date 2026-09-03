// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import Testing

@testable import cmux

/// CONTRACT rows 12, 13, 15, 76, 117, 120, 125, 126, 127.
@MainActor
struct CarouselTopBarViewModelTests {
    // MARK: - Harness

    private struct Harness {
        let directory: TemporaryDirectory
        let root: CarouselDataRoot
        let store: StatuslineSnapshotStore
        let reader: CarouselSessionStateReader
        var now: Date

        init(now: Date = Date(timeIntervalSince1970: 1_788_386_000)) throws {
            directory = try TemporaryDirectory()
            root = CarouselDataRoot(url: directory.url, source: .environmentOverride, freshness: .unknown)
            try FileManager.default.createDirectory(at: root.statuslineSnapshotsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: root.sessionsDirectory, withIntermediateDirectories: true)
            let captured = now
            store = StatuslineSnapshotStore(dataRoot: root, now: { captured })
            reader = CarouselSessionStateReader(dataRoot: root)
            self.now = now
        }

        struct UnsafeSessionIdentifier: Error { let value: String }

        func writeSnapshot(_ data: Data, sessionId: String) throws {
            guard let url = root.statuslineSnapshotURL(sessionId: sessionId) else {
                throw UnsafeSessionIdentifier(value: sessionId)
            }
            try data.write(to: url)
        }

        func writeRegistry(sessionId: String, status: String) throws {
            try CarouselFixtures.sessionRegistryJSON(sessionId: sessionId, status: status)
                .write(to: root.sessionsDirectory.appending(path: "\(sessionId).json"))
        }

        func state(for session: CarouselSession?) -> CarouselTopBarViewState {
            store.reload()
            return CarouselTopBarViewModel.makeState(
                centredSession: session,
                store: store,
                sessionStates: reader,
                now: now
            )
        }
    }

    // MARK: - Row 12

    @Test("Row 12: the model canary in the snapshot is the string the bar renders")
    func modelCanaryRenders() throws {
        let harness = try Harness()
        let sessionId = "row12-session"
        let canary = "U5-MODEL-CANARY-ALPHA"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, modelDisplayName: canary, capturedAt: harness.now),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        #expect(state.model == .named(canary))
    }

    @Test("Row 12 + 125: with TWO sessions carrying different canaries, the CENTRED one wins")
    func modelFollowsCentredSessionNotTheOnlySession() throws {
        let harness = try Harness()
        let first = "row12-session-a"
        let second = "row12-session-b"
        for (id, canary, status) in [(first, "CANARY-A", "busy"), (second, "CANARY-B", "idle")] {
            try harness.writeRegistry(sessionId: id, status: status)
            try harness.writeSnapshot(
                CarouselFixtures.snapshotJSON(sessionId: id, modelDisplayName: canary, capturedAt: harness.now),
                sessionId: id
            )
        }
        let a = harness.state(for: CarouselFixtures.session(claudeSessionId: first))
        let b = harness.state(for: CarouselFixtures.session(claudeSessionId: second))
        // The assertion that matters: the two states DIFFER. A join that ignored
        // the centred card would return the same value twice and still pass a
        // one-session test.
        #expect(a.model == .named("CANARY-A"))
        #expect(b.model == .named("CANARY-B"))
        #expect(a.model != b.model)
        #expect(a.agentActivity == .running)
        #expect(b.agentActivity == .idle)
    }

    @Test("Row 125: the bind callback moves the whole bar to the newly centred session")
    func bindFollowsCentreChanges() throws {
        let harness = try Harness()
        let first = "row125-a"
        let second = "row125-b"
        try harness.writeRegistry(sessionId: first, status: "idle")
        try harness.writeRegistry(sessionId: second, status: "busy")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: first, modelDisplayName: "FIRST", fiveHourPercent: 10, sevenDayPercent: 20, capturedAt: harness.now),
            sessionId: first
        )
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: second, modelDisplayName: "SECOND", fiveHourPercent: 90, sevenDayPercent: 80, capturedAt: harness.now),
            sessionId: second
        )
        harness.store.reload()

        let capturedNow = harness.now
        let model = CarouselTopBarViewModel(store: harness.store, sessionStates: harness.reader, now: { capturedNow })
        let routing = FakeCarouselSessionRouting(centredSession: CarouselFixtures.session(claudeSessionId: first))
        model.bind(routing: routing)
        #expect(model.state.model == .named("FIRST"))
        #expect(model.state.fiveHour == .measured(percent: 10, resetsAt: Date(timeIntervalSince1970: 1_788_400_800)))

        routing.centre(on: CarouselFixtures.session(claudeSessionId: second))
        #expect(model.state.model == .named("SECOND"))
        #expect(model.state.fiveHour == .measured(percent: 90, resetsAt: Date(timeIntervalSince1970: 1_788_400_800)))
        #expect(model.state.agentActivity == .running)
    }

    // MARK: - Row 13

    @Test("Row 13: used_percentage 63.4 with a 200k window gives a 0.634 fill and the derived label")
    func compactionMeterFill() throws {
        let harness = try Harness()
        let sessionId = "row13-session"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, contextUsedPercentage: 63.4, contextWindowSize: 200_000, capturedAt: harness.now),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        guard case .measured(let fraction, let usedTokens, let windowSize) = state.compaction else {
            Issue.record("expected a measured compaction state, got \(state.compaction)")
            return
        }
        #expect(abs(fraction - 0.634) < 0.005)
        #expect(windowSize == 200_000)
        // 1000 input + 20 cache-creation + 125_780 cache-read, the input-token
        // basis the statusline's own percentage uses.
        #expect(usedTokens == 126_800)
        let label = CompactionMeterView.measuredLabel(fraction: fraction, usedTokens: usedTokens, windowSize: windowSize)
        #expect(label.contains("63%"))
        #expect(label.contains("126k"))
        #expect(label.contains("200k"))
    }

    @Test("Row 13: current_usage null renders the defined empty state, NOT a zero fill")
    func compactionNullCurrentUsageIsNotZero() throws {
        let harness = try Harness()
        let sessionId = "row13-null"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(
                sessionId: sessionId,
                contextUsedPercentage: 63.4,   // deliberately still present and stale
                includeCurrentUsage: false,
                capturedAt: harness.now
            ),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        #expect(state.compaction == .awaitingFirstResponse)
        // The distinction the row exists for: an empty state is not a zero.
        #expect(state.compaction != .measured(fraction: 0, usedTokens: nil, windowSize: nil))
    }

    // MARK: - Rows 15 and 120

    @Test("Row 15: five_hour 62 and seven_day 41 render as those percentages with reset times")
    func usageMetersRenderBothWindows() throws {
        let harness = try Harness()
        let sessionId = "row15-session"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, fiveHourPercent: 62, sevenDayPercent: 41, capturedAt: harness.now),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        #expect(state.fiveHour == .measured(percent: 62, resetsAt: Date(timeIntervalSince1970: 1_788_400_800)))
        #expect(state.sevenDay == .measured(percent: 41, resetsAt: Date(timeIntervalSince1970: 1_788_984_000)))
        #expect(state.fiveHour.severity == .elevated)
        #expect(state.sevenDay.severity == .healthy)
    }

    @Test("Row 15 + 120: absent rate_limits renders unavailable, never a fabricated percentage")
    func absentRateLimitsIsUnavailable() throws {
        let harness = try Harness()
        let sessionId = "row15-absent"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, includeRateLimits: false, capturedAt: harness.now),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        #expect(state.fiveHour == .unavailable)
        #expect(state.sevenDay == .unavailable)
        #expect(state.fiveHour.severity == nil)
        // The model and context still render — the unavailability is scoped to
        // the field that is missing, not to the whole bar.
        #expect(state.model != .unavailable)
    }

    // MARK: - Row 76

    @Test("Row 76: a snapshot older than 60 s renders the stale state with its capture time")
    func staleSnapshotRendersStale() throws {
        let harness = try Harness()
        let sessionId = "row76-stale"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        let captured = harness.now.addingTimeInterval(-61)
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, capturedAt: captured),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        guard case .stale(let age, let capturedAt) = state.liveness else {
            Issue.record("expected stale, got \(state.liveness)")
            return
        }
        #expect(abs(age - 61) < 1)
        #expect(abs(capturedAt.timeIntervalSince(captured)) < 1)
        // Nothing measured survives into the stale state.
        #expect(state.compaction == .unavailable)
        #expect(state.fiveHour == .unavailable)
        #expect(state.sevenDay == .unavailable)
        #expect(state.suppressesLiveNumbers)
        #expect(CarouselTopBarStatusView.message(for: state).contains("stale"))
    }

    @Test("Row 76: a snapshot just inside 60 s is live")
    func freshSnapshotIsLive() throws {
        let harness = try Harness()
        let sessionId = "row76-fresh"
        try harness.writeRegistry(sessionId: sessionId, status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, capturedAt: harness.now.addingTimeInterval(-59)),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        #expect(state.liveness == .live)
        #expect(!state.suppressesLiveNumbers)
    }

    // MARK: - Rows 117 and 126

    @Test("Row 126: a session that has left the registry renders the ended state, not its last numbers")
    func deadSessionRendersEnded() throws {
        let harness = try Harness()
        let sessionId = "row126-dead"
        // Registry has a DIFFERENT session, so the directory is readable and this
        // one is provably gone rather than merely unknown.
        try harness.writeRegistry(sessionId: "some-other-session", status: "idle")
        try harness.writeSnapshot(
            CarouselFixtures.snapshotJSON(sessionId: sessionId, capturedAt: harness.now),
            sessionId: sessionId
        )
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
        #expect(state.liveness == .deadSession)
        #expect(state.fiveHour == .unavailable)
        #expect(state.compaction == .unavailable)
        #expect(state.agentActivity == .unknown)
        #expect(CarouselTopBarStatusView.message(for: state) == "session ended")
    }

    @Test("Row 117: an unreadable data root names the source instead of rendering an empty bar")
    func unreadableRootIsDegradedNotEmpty() throws {
        let missing = CarouselDataRoot(
            url: URL(fileURLWithPath: "/nonexistent/u5/mirror"),
            source: .mirror, freshness: .unknown
        )
        let store = StatuslineSnapshotStore(dataRoot: missing)
        store.reload()
        #expect(!store.directoryIsReadable)
        let state = CarouselTopBarViewModel.makeState(
            centredSession: CarouselFixtures.session(claudeSessionId: "any-session"),
            store: store,
            sessionStates: CarouselSessionStateReader(dataRoot: missing),
            now: Date()
        )
        let message = try #require(state.degradedSourceDescription)
        #expect(message.contains("Mirror of the Hive"))
        #expect(message.contains("/nonexistent/u5/mirror"))
    }

    @Test("A card with no Claude Code session says so rather than showing the previous card's numbers")
    func nonClaudeCardShowsNoSession() throws {
        let harness = try Harness()
        let state = harness.state(for: CarouselFixtures.session(claudeSessionId: nil))
        #expect(state.liveness == .noSession)
        #expect(state.model == .unavailable)
        #expect(state.fiveHour == .unavailable)
    }

    // MARK: - Row 127

    @Test("Row 127: the registry status drives the signal, and an unknown status never reads as idle")
    func agentActivityFromRegistry() throws {
        for (status, expected) in [("busy", CarouselAgentActivity.running), ("idle", .idle), ("wedged", .unknown)] {
            let harness = try Harness()
            let sessionId = "row127-\(status)"
            try harness.writeRegistry(sessionId: sessionId, status: status)
            try harness.writeSnapshot(
                CarouselFixtures.snapshotJSON(sessionId: sessionId, capturedAt: harness.now),
                sessionId: sessionId
            )
            let state = harness.state(for: CarouselFixtures.session(claudeSessionId: sessionId))
            #expect(state.agentActivity == expected, "status \(status) should map to \(expected)")
        }
    }

    @Test("Row 127: a transcript older than the max age reads unknown, never idle")
    func staleTranscriptIsUnknownNotIdle() throws {
        let directory = try TemporaryDirectory()
        let transcript = directory.url.appending(path: "transcript.jsonl")
        try #"{"type":"assistant"}"#.data(using: .utf8)!.write(to: transcript)
        let now = Date()
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-(CarouselAgentActivityReader.staleAfter + 10))],
            ofItemAtPath: transcript.path
        )
        #expect(CarouselAgentActivityReader.activity(transcriptPath: transcript.path, now: now) == .unknown)
    }

    @Test("Row 127: an assistant entry carrying tool_use is RUNNING, not idle")
    func assistantMidToolCallIsRunning() throws {
        // The defect U4 found and measured. Role alone cannot separate a finished
        // turn from one that is mid-tool-call: both end on an assistant entry.
        // Counted on a real 6,178-entry Hive transcript: 39 assistant entries
        // carrying only tool_use, 30 carrying only thinking, 33 carrying only text.
        // Only the last of those is turn-final.
        typealias Reader = CarouselAgentActivityReader
        #expect(Reader.classify(Reader.Entry(type: "assistant", blockTypes: ["tool_use"])) == .running)
        #expect(Reader.classify(Reader.Entry(type: "assistant", blockTypes: ["text", "tool_use"])) == .running)
        #expect(Reader.classify(Reader.Entry(type: "assistant", blockTypes: ["thinking"])) == .running)
        #expect(Reader.classify(Reader.Entry(type: "assistant", blockTypes: ["text"])) == .idle)
        #expect(Reader.classify(Reader.Entry(type: "user", blockTypes: ["tool_result"])) == .running)
        #expect(Reader.classify(Reader.Entry(type: "user", blockTypes: ["text"])) == .running)
        #expect(Reader.classify(nil) == .unknown)
    }

    @Test("Row 127: bookkeeping entries are skipped, not classified")
    func bookkeepingEntriesAreSkipped() throws {
        // Measured, not assumed: the FINAL line of a real transcript was
        // type=attachment. A reader that classifies the literal last line reports
        // unknown most of the time, which is a silent failure rather than a wrong
        // answer, and would have looked like a working signal in every fixture.
        let directory = try TemporaryDirectory()
        let transcript = directory.url.appending(path: "t.jsonl")
        let lines = [
            #"{"type":"user","message":{"content":"go"}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
            #"{"type":"attachment"}"#,
            #"{"type":"queue-operation"}"#,
            #"{"type":"permission-mode"}"#,
        ].joined(separator: "\n") + "\n"
        try lines.data(using: .utf8)!.write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: transcript.path)

        let entry = try #require(CarouselAgentActivityReader.lastConversationalEntry(url: transcript))
        #expect(entry.type == "assistant")
        #expect(entry.blockTypes == ["tool_use"])
        #expect(CarouselAgentActivityReader.activity(transcriptPath: transcript.path, now: Date()) == .running)
    }

    @Test("Row 127: a finished turn reads idle through the same path")
    func finishedTurnIsIdle() throws {
        let directory = try TemporaryDirectory()
        let transcript = directory.url.appending(path: "t.jsonl")
        let lines = [
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#,
            #"{"type":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"done"}]}}"#,
            #"{"type":"attachment"}"#,
        ].joined(separator: "\n") + "\n"
        try lines.data(using: .utf8)!.write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: transcript.path)
        #expect(CarouselAgentActivityReader.activity(transcriptPath: transcript.path, now: Date()) == .idle)
    }

    @Test("Row 127: a missing transcript is unknown, not idle")
    func missingTranscriptIsUnknown() {
        #expect(CarouselAgentActivityReader.activity(transcriptPath: "/nonexistent/x.jsonl", now: Date()) == .unknown)
        #expect(CarouselAgentActivityReader.activity(transcriptPath: nil, now: Date()) == .unknown)
    }
}
