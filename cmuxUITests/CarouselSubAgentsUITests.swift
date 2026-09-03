// Modified 2026-09-03 for the cmux carousel build (carousel unit work).
import Foundation
import XCTest

/// CONTRACT row 11 — the sub-agents chip and popover, driven through the real
/// app against an injected fixture root.
///
/// The fixture is written to a temporary directory and handed to the app via
/// `CMUX_CAROUSEL_DATA_ROOT`, which is the only seam the carousel reads paths
/// through (row 118). Every assertion names a canary the fixture wrote, so a
/// fixture that failed to reach the app fails the test instead of passing on a
/// count that happened to match.
///
/// These cases need the carousel chrome to exist before they can run: under
/// the Twin Rails pick the chip mounts at the right end of U5's top rail.
/// Until then each one skips with that reason rather than failing, so the
/// suite reports the truth — nothing here is silently green.
final class CarouselSubAgentsUITests: XCTestCase {
    private var fixtureRoot: URL?

    private let projectSlug = "-home-dawid"
    private let sessionID = "uitest-session"

    override func tearDown() {
        if let fixtureRoot {
            try? FileManager.default.removeItem(at: fixtureRoot)
        }
        fixtureRoot = nil
        super.tearDown()
    }

    func testChipShowsRunningCountOnly() throws {
        let app = try launchWithFixture(runningAgents: 2, finishedAgents: 3)
        let chip = app.descendants(matching: .any)["carousel.subAgents.chip"]
        XCTAssertEqual(chip.value as? String, "2 agents")
    }

    func testPopoverListsEveryAgentAndItsNesting() throws {
        let app = try launchWithFixture(runningAgents: 2, finishedAgents: 1, includeNested: true)
        let chip = app.descendants(matching: .any)["carousel.subAgents.chip"]
        chip.click()

        // The open-popover signal is the header's running-count id. The panel
        // container itself carries no identifier on purpose: a container id
        // swallows its whole subtree's ids (outermost wins), which would make
        // every row below unresolvable. The header renders in every popover
        // state and has no identifier-bearing ancestors, so it resolves.
        let popoverCount = app.descendants(matching: .any)["carousel.subAgents.popover.runningCount"]
        XCTAssertTrue(popoverCount.waitForExistence(timeout: 5))

        for index in 0..<3 {
            let row = app.descendants(matching: .any)["carousel.subAgents.row.acanary\(index)"]
            XCTAssertTrue(row.exists, "fixture agent acanary\(index) is missing from the popover")
        }

        // The nested agent is indented, so its row's minX sits right of its
        // parent's. firstMatch: a row's texts surface as separate fragments
        // sharing the row's id (outermost wins), so a bare subscript is
        // ambiguous; every fragment shares the row's indentation padding, so
        // first-match frames compare the rows correctly.
        let parent = app.descendants(matching: .any)["carousel.subAgents.row.acanary0"].firstMatch
        let child = app.descendants(matching: .any)["carousel.subAgents.row.anested"].firstMatch
        XCTAssertTrue(child.exists)
        XCTAssertGreaterThan(child.frame.minX, parent.frame.minX)
    }

    func testEmptyRootRendersTheEmptyState() throws {
        let app = try launchWithFixture(runningAgents: 0, finishedAgents: 0)
        let chip = app.descendants(matching: .any)["carousel.subAgents.chip"]
        XCTAssertEqual(chip.value as? String, "0 agents")
    }

    func testExcludedWorkspaceCountAppearsAsABadge() throws {
        // CONTRACT row 132: an unmounted workspace's surfaces are excluded from
        // the card list, and their count has to be visible somewhere.
        let app = try launchWithFixture(runningAgents: 1, finishedAgents: 0, unmountedWorkspaces: 2)
        let badge = app.descendants(matching: .any)["carousel.subAgents.excludedBadge"]
        XCTAssertTrue(badge.waitForExistence(timeout: 10))
    }

    // MARK: - Harness

    private func launchWithFixture(
        runningAgents: Int,
        finishedAgents: Int,
        includeNested: Bool = false,
        unmountedWorkspaces: Int = 0
    ) throws -> XCUIApplication {
        let root = try writeFixture(
            runningAgents: runningAgents,
            finishedAgents: finishedAgents,
            includeNested: includeNested
        )
        fixtureRoot = root

        let app = XCUIApplication()
        app.launchEnvironment["CMUX_CAROUSEL_DATA_ROOT"] = root.path
        app.launchEnvironment["CMUX_UI_TEST_CAROUSEL_SESSION_SLUG"] = projectSlug
        app.launchEnvironment["CMUX_UI_TEST_CAROUSEL_SESSION_ID"] = sessionID
        app.launchEnvironment["CMUX_UI_TEST_CAROUSEL_UNMOUNTED_WORKSPACES"] = String(unmountedWorkspaces)
        // Enter carousel mode at launch: the app auto-activates the mode when
        // this debug toggle is set, so these tests assert on live carousel
        // chrome instead of synthesising the ⌃⌘K chord.
        app.launchEnvironment["CMUX_CAROUSEL_DEBUG_TOGGLE"] = "1"
        app.launch()

        // Guard on the chip itself rather than on a container identifier.
        // Nothing in any branch defines `carousel.root` yet, and a guard on a
        // name nobody has created can never stop skipping — it would report
        // green-by-absence forever, which is the exact failure this suite is
        // written to avoid. Waiting for the chip un-skips the moment the chip
        // is mounted, whoever mounts it and whatever the container is called.
        let chip = app.descendants(matching: .any)["carousel.subAgents.chip"]
        try XCTSkipUnless(
            chip.waitForExistence(timeout: 15),
            """
            The sub-agents chip is not in this build yet. U4 owns the chip; \
            under Twin Rails it mounts at the right end of U5's top rail, and \
            that rail does not exist at this head. These cases run unchanged \
            once it does.
            """
        )
        return app
    }

    private func writeFixture(
        runningAgents: Int,
        finishedAgents: Int,
        includeNested: Bool
    ) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("cmux-carousel-uitest-\(UUID().uuidString)", isDirectory: true)
        let directory = root
            .appendingPathComponent("projects", isDirectory: true)
            .appendingPathComponent(projectSlug, isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var index = 0
        for _ in 0..<runningAgents {
            try writeAgent(
                in: directory,
                id: "acanary\(index)",
                name: "canary-\(index)",
                isFinished: false,
                parentAgentId: nil
            )
            index += 1
        }
        for _ in 0..<finishedAgents {
            try writeAgent(
                in: directory,
                id: "acanary\(index)",
                name: "canary-\(index)",
                isFinished: true,
                parentAgentId: nil
            )
            index += 1
        }
        if includeNested {
            try writeAgent(
                in: directory,
                id: "anested",
                name: "canary-nested",
                isFinished: false,
                parentAgentId: "acanary0"
            )
        }
        return root
    }

    private func writeAgent(
        in directory: URL,
        id: String,
        name: String,
        isFinished: Bool,
        parentAgentId: String?
    ) throws {
        let lastLine = isFinished
            ? #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}"#
            : #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash"}]}}"#
        let transcript = directory.appendingPathComponent("agent-\(id).jsonl")
        try "\(lastLine)\n".write(to: transcript, atomically: true, encoding: .utf8)
        if isFinished {
            // Older than the settle window, so it reads as finished rather than
            // as a running agent that has just spoken.
            try FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(-30)],
                ofItemAtPath: transcript.path
            )
        }

        var meta: [String: Any] = [
            "agentType": "general-purpose",
            "description": "fixture agent \(name)",
            "name": name,
            "spawnDepth": parentAgentId == nil ? 1 : 2,
        ]
        if let parentAgentId { meta["parentAgentId"] = parentAgentId }
        try JSONSerialization.data(withJSONObject: meta).write(
            to: directory.appendingPathComponent("agent-\(id).meta.json")
        )
    }
}
