// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// CONTRACT row 118's controls, asserted against **U7's** provider rather than a
/// second one. U5 deleted its own `CarouselDataRoot` when it rebased onto
/// `carousel/u7`; U7 shipped the provider and the seam gate but no test target
/// files, so these are the only executable controls the row has.
@MainActor
struct CarouselStatuslineSeamTests {
    @Test("Row 118: CMUX_CAROUSEL_DATA_ROOT wins and NEVER falls back")
    func environmentOverrideWinsAndDoesNotFallBack() {
        let root = CarouselDataRoot.resolve(
            environment: ["CMUX_CAROUSEL_DATA_ROOT": "/tmp/u5-fixture-root"],
            settingPath: "/tmp/setting-root"
        )
        #expect(root.url.path == "/tmp/u5-fixture-root")
        #expect(root.source == .environmentOverride)
    }

    @Test("Row 118 NEGATIVE CONTROL: an EMPTY injected root shows none of the real Hive sessions")
    func emptyRootShowsNothing() throws {
        // The control the row calls mandatory. A provider that silently fell back to
        // the real root would pass every positive test and fail nothing without this.
        let empty = try TemporaryDirectory()
        let root = CarouselDataRoot(url: empty.url, source: .environmentOverride, freshness: .unknown)

        let store = StatuslineSnapshotStore(dataRoot: root)
        store.reload()
        #expect(store.records.isEmpty)

        let reader = CarouselSessionStateReader(dataRoot: root)
        #expect(reader.readAll() == nil, "no sessions directory means no SOURCE, not an empty list")
        #expect(reader.presence(ofSessionId: "32999e8f-c459-4e76-aed9-4f4b6e48df79") == .unknown)

        let state = CarouselTopBarViewModel.makeState(
            centredSession: CarouselFixtures.session(claudeSessionId: "32999e8f-c459-4e76-aed9-4f4b6e48df79"),
            store: store,
            sessionStates: reader,
            now: Date()
        )
        #expect(state.model == .unavailable)
        #expect(state.fiveHour == .unavailable)
        #expect(state.sevenDay == .unavailable)
    }

    @Test("Row 118 POSITIVE CONTROL: the injected root's OWN canary is what surfaces")
    func injectedRootCanarySurfaces() throws {
        let directory = try TemporaryDirectory()
        let root = CarouselDataRoot(url: directory.url, source: .environmentOverride, freshness: .unknown)
        try FileManager.default.createDirectory(at: root.statuslineSnapshotsDirectory, withIntermediateDirectories: true)
        let canary = "U5-CANARY-MODEL-NAME"
        let sessionId = "fixture-positive-control"
        let url = try #require(root.statuslineSnapshotURL(sessionId: sessionId))
        try CarouselFixtures.snapshotJSON(sessionId: sessionId, modelDisplayName: canary, capturedAt: Date())
            .write(to: url)

        let store = StatuslineSnapshotStore(dataRoot: root)
        store.reload()
        let record = try #require(store.record(forSessionId: sessionId))
        #expect(record.snapshot.model?.displayName == canary)
    }

    @Test("A session id that is not path-safe is rejected, never sanitised into a different name")
    func rejectsUnsafeSessionIdentifiers() {
        let root = CarouselDataRoot(url: URL(fileURLWithPath: "/tmp/u5-root"), source: .environmentOverride, freshness: .unknown)
        for unsafe in ["../../etc/passwd", "a/b", ".hidden", "", "..", "with space", "semi;colon"] {
            #expect(root.statuslineSnapshotURL(sessionId: unsafe) == nil, "\(unsafe) must be rejected")
            #expect(!CarouselDataRoot.isPathSafeIdentifier(unsafe))
        }
        for safe in ["32999e8f-c459-4e76-aed9-4f4b6e48df79", "abc_123.def"] {
            #expect(CarouselDataRoot.isPathSafeIdentifier(safe))
        }
        #expect(root.statuslineSnapshotURL(sessionId: "abc-123")?.path == "/tmp/u5-root/statusline-snapshots/abc-123.json")
    }

    @Test("Row 117: a stale mirror stamp names the host instead of rendering an empty bar")
    func staleMirrorNamesTheHost() {
        let root = CarouselDataRoot(
            url: URL(fileURLWithPath: "/tmp/u5-mirror"),
            source: .mirror,
            freshness: .stale(age: 312, host: "hive")
        )
        let description = root.degradedDescription
        #expect(description.contains("hive"))
        #expect(description.contains("312"))
        #expect(description.contains("/tmp/u5-mirror"))
    }
}
