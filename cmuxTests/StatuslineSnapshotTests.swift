import Foundation
import Testing

@testable import cmux

/// CONTRACT rows 76 and 120 — the parser against the payload that actually
/// arrives, not only against the fixtures the contract describes.
struct StatuslineSnapshotTests {
    @Test("Row 120: the REAL payload captured on the Hive parses, with rate_limits present and numeric")
    func realPayloadParses() throws {
        let snapshot = try JSONDecoder().decode(StatuslineSnapshot.self, from: CarouselFixtures.realCapturedPayload)
        let limits = try #require(snapshot.rateLimits, "row 120 fails outright if rate_limits is absent")
        let fiveHour = try #require(limits.fiveHour?.usedPercentage)
        let sevenDay = try #require(limits.sevenDay?.usedPercentage)
        #expect(fiveHour == 60)
        #expect(sevenDay == 12)
        #expect(limits.fiveHour?.resetDate == Date(timeIntervalSince1970: 1_788_400_800))
        #expect(snapshot.model?.displayName == "Fable 5.1")
    }

    @Test("Row 120: the live payload's integer percentages decode as Double alongside fractional fixtures")
    func integerAndFractionalPercentagesBothDecode() throws {
        // Live payloads emit `46`; the contract's fixtures use `63.4`. Both must
        // land in the same field without a second code path.
        let live = try JSONDecoder().decode(StatuslineSnapshot.self, from: CarouselFixtures.realCapturedPayload)
        #expect(live.contextWindow?.usedPercentage == 46)
        let fixture = try JSONDecoder().decode(
            StatuslineSnapshot.self,
            from: CarouselFixtures.snapshotJSON(sessionId: "x", contextUsedPercentage: 63.4, capturedAt: Date())
        )
        #expect(fixture.contextWindow?.usedPercentage == 63.4)
    }

    @Test("The live payload's 1M context window is honoured, not replaced by the documented 200k default")
    func extendedContextWindowIsHonoured() throws {
        let snapshot = try JSONDecoder().decode(StatuslineSnapshot.self, from: CarouselFixtures.realCapturedPayload)
        #expect(snapshot.contextWindow?.contextWindowSize == 1_000_000)
        guard case .measured(let fraction, _, let windowSize) = CarouselTopBarViewModel.compactionState(snapshot) else {
            Issue.record("expected a measured state")
            return
        }
        #expect(windowSize == 1_000_000)
        #expect(abs(fraction - 0.46) < 0.005)
    }

    @Test("Unknown top-level keys in a real payload do not break decoding")
    func unknownKeysAreIgnored() throws {
        // scratchpad_dir, output_style, prompt_cache, effort, cost and
        // exceeds_200k_tokens are all present in the live payload and modelled by
        // none of our types. Decoding must be unaffected.
        #expect(CarouselFixtures.realCapturedPayloadJSON.contains("scratchpad_dir"))
        #expect(CarouselFixtures.realCapturedPayloadJSON.contains("prompt_cache"))
        #expect(throws: Never.self) {
            _ = try JSONDecoder().decode(StatuslineSnapshot.self, from: CarouselFixtures.realCapturedPayload)
        }
    }

    @Test("Every field is genuinely optional — a payload with only a session_id decodes")
    func minimalPayloadDecodes() throws {
        let snapshot = try JSONDecoder().decode(
            StatuslineSnapshot.self,
            from: Data(#"{"session_id":"only-id"}"#.utf8)
        )
        #expect(snapshot.sessionId == "only-id")
        #expect(snapshot.model == nil)
        #expect(snapshot.contextWindow == nil)
        #expect(snapshot.rateLimits == nil)
        #expect(CarouselTopBarViewModel.modelState(snapshot) == .unavailable)
        #expect(CarouselTopBarViewModel.compactionState(snapshot) == .unavailable)
        #expect(CarouselTopBarViewModel.usageState(snapshot.rateLimits?.fiveHour) == .unavailable)
    }

    @Test("Row 76: the in-payload capture time is preferred over the file's mtime")
    func inPayloadCaptureTimeWins() throws {
        let stamped = Date(timeIntervalSince1970: 1_788_000_000)
        let misleadingMtime = Date()   // what a mirror that rewrites mtime would leave
        let record = try StatuslineSnapshotRecord.decode(
            data: CarouselFixtures.snapshotJSON(sessionId: "x", capturedAt: stamped),
            fileModificationDate: misleadingMtime
        )
        #expect(record.capturedAtIsAuthoritative)
        #expect(abs(record.capturedAt.timeIntervalSince(stamped)) < 1)
        // The defect this prevents: without the in-payload stamp, a snapshot from
        // 2026-04 would look seconds old.
        #expect(record.age(now: misleadingMtime) > 60)
    }

    @Test("Row 76: without the in-payload stamp the file mtime is used, and the fallback is recorded")
    func mtimeFallbackIsRecorded() throws {
        let mtime = Date(timeIntervalSince1970: 1_788_100_000)
        let record = try StatuslineSnapshotRecord.decode(
            data: Data(#"{"session_id":"x"}"#.utf8),
            fileModificationDate: mtime
        )
        #expect(!record.capturedAtIsAuthoritative)
        #expect(record.capturedAt == mtime)
    }
}

/// The session registry reader, against the shape verified live on the Hive.
struct CarouselSessionStateReaderTests {
    @Test("The registry's sessionId is the statusline snapshot's filename — the row 125 join")
    func registryJoinsToSnapshotFilename() throws {
        let directory = try TemporaryDirectory()
        let root = CarouselDataRoot(url: directory.url, origin: .environmentOverride)
        try FileManager.default.createDirectory(at: root.sessionsDirectory, withIntermediateDirectories: true)
        let sessionId = "32999e8f-c459-4e76-aed9-4f4b6e48df79"
        try CarouselFixtures.sessionRegistryJSON(sessionId: sessionId, status: "busy", name: "dawid-b2")
            .write(to: root.sessionsDirectory.appending(path: "1893839.json"))

        let reader = CarouselSessionStateReader(dataRoot: root)
        guard case .present(let state) = reader.presence(ofSessionId: sessionId) else {
            Issue.record("expected the session to be present")
            return
        }
        #expect(state.name == "dawid-b2")
        #expect(state.status == "busy")
        #expect(state.activity == .running)
        // D-4's card-to-session join key.
        #expect(state.tmuxTarget == "hive-claude:@10.%10")
    }

    @Test("A readable registry that lacks the session reports gone; an unreadable one reports unknown")
    func goneVersusUnknown() throws {
        let directory = try TemporaryDirectory()
        let root = CarouselDataRoot(url: directory.url, origin: .environmentOverride)
        // No sessions directory at all: the source is missing, so nothing may be
        // declared dead. This distinction is what stops a down mirror from
        // rendering every card as an ended session.
        #expect(CarouselSessionStateReader(dataRoot: root).presence(ofSessionId: "abc") == .unknown)

        try FileManager.default.createDirectory(at: root.sessionsDirectory, withIntermediateDirectories: true)
        try CarouselFixtures.sessionRegistryJSON(sessionId: "other", status: "idle")
            .write(to: root.sessionsDirectory.appending(path: "1.json"))
        #expect(CarouselSessionStateReader(dataRoot: root).presence(ofSessionId: "abc") == .gone)
    }
}
