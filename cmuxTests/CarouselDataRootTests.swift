import Foundation
import Testing

@testable import cmux

/// CONTRACT row 118 / D-5 — the injectable path provider, with the negative
/// control the row makes mandatory.
struct CarouselDataRootTests {
    @Test("Row 118: CMUX_CAROUSEL_DATA_ROOT wins over every other source")
    func environmentOverrideWins() {
        let root = CarouselDataRoot.resolve(
            environment: [CarouselDataRoot.environmentKey: "/tmp/u5-fixture-root"],
            settingsPath: "/tmp/settings-root"
        )
        #expect(root.url.path == "/tmp/u5-fixture-root")
        #expect(root.origin == .environmentOverride)
    }

    @Test("Row 118: the settings key is used when no environment override is set")
    func settingsUsedWithoutOverride() {
        let root = CarouselDataRoot.resolve(environment: [:], settingsPath: "/tmp/settings-root")
        #expect(root.url.path == "/tmp/settings-root")
        #expect(root.origin == .settings)
    }

    @Test("Row 118: an empty or whitespace override does not silently win")
    func blankOverrideIsIgnored() {
        for blank in ["", "   "] {
            let root = CarouselDataRoot.resolve(
                environment: [CarouselDataRoot.environmentKey: blank],
                settingsPath: "/tmp/settings-root"
            )
            #expect(root.origin == .settings)
        }
    }

    @Test("Row 118: with nothing configured the root is the mirror, not the real home")
    func defaultsToMirror() {
        let root = CarouselDataRoot.resolve(environment: [:], settingsPath: nil)
        #expect(root.origin == .mirror)
        #expect(root.url.path.contains("carousel-mirror"))
        #expect(!root.url.path.hasSuffix("/.claude"))
    }

    @Test("Row 118: every carousel path hangs off the injected root")
    func subdirectoriesDeriveFromRoot() {
        let root = CarouselDataRoot(url: URL(fileURLWithPath: "/tmp/u5-root"), origin: .environmentOverride)
        #expect(root.sessionsDirectory.path == "/tmp/u5-root/sessions")
        #expect(root.projectsDirectory.path == "/tmp/u5-root/projects")
        #expect(root.statuslineSnapshotsDirectory.path == "/tmp/u5-root/statusline-snapshots")
        #expect(root.statuslineSnapshotURL(sessionId: "abc-123")?.path == "/tmp/u5-root/statusline-snapshots/abc-123.json")
    }

    @Test("A session id that is not path-safe is rejected, never sanitised into a different name")
    func rejectsUnsafeSessionIdentifiers() {
        let root = CarouselDataRoot(url: URL(fileURLWithPath: "/tmp/u5-root"), origin: .environmentOverride)
        for unsafe in ["../../etc/passwd", "a/b", ".hidden", "", "..", "with space", "semi;colon"] {
            #expect(root.statuslineSnapshotURL(sessionId: unsafe) == nil, "\(unsafe) should be rejected")
            #expect(!CarouselDataRoot.isPathSafeIdentifier(unsafe))
        }
        for safe in ["32999e8f-c459-4e76-aed9-4f4b6e48df79", "abc_123.def"] {
            #expect(CarouselDataRoot.isPathSafeIdentifier(safe))
        }
    }
}

/// The row-118 negative control, which the row calls mandatory: a provider that
/// silently falls back to the real root would pass every positive test and fail
/// nothing without this.
@MainActor
struct CarouselDataRootNegativeControlTests {
    @Test("Row 118 negative control: an EMPTY injected root yields no sessions at all")
    func emptyRootShowsNothing() throws {
        let empty = try TemporaryDirectory()
        let root = CarouselDataRoot(url: empty.url, origin: .environmentOverride)

        let store = StatuslineSnapshotStore(dataRoot: root)
        store.reload()
        #expect(store.records.isEmpty, "an empty root must yield zero snapshots")

        let reader = CarouselSessionStateReader(dataRoot: root)
        #expect(reader.readAll() == nil, "a root with no sessions directory reports no source, not an empty list")
        #expect(reader.presence(ofSessionId: "32999e8f-c459-4e76-aed9-4f4b6e48df79") == .unknown)
    }

    @Test("Row 118 positive control: the injected root's OWN canary is what surfaces")
    func injectedRootCanarySurfaces() throws {
        let directory = try TemporaryDirectory()
        let root = CarouselDataRoot(url: directory.url, origin: .environmentOverride)
        try FileManager.default.createDirectory(at: root.statuslineSnapshotsDirectory, withIntermediateDirectories: true)
        let canary = "U5-CANARY-MODEL-NAME"
        let sessionId = "fixture-positive-control"
        try CarouselFixtures.snapshotJSON(
            sessionId: sessionId,
            modelDisplayName: canary,
            capturedAt: Date()
        ).write(to: root.statuslineSnapshotURL(sessionId: sessionId)!)

        let store = StatuslineSnapshotStore(dataRoot: root)
        store.reload()
        let record = try #require(store.record(forSessionId: sessionId))
        #expect(record.snapshot.model?.displayName == canary)
        #expect(CarouselTopBarViewModel.modelState(record.snapshot) == .named(canary))
    }
}

/// A temp directory that removes itself.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "cmux-u5-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }
}
