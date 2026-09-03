# U4 local verification — 2026-09-03 (Mac session, repo /Users/dawid/code/cmux-u4)

Handoff scope: execute the tests committed in 82b0835c34 ("Parse-clean; executed
counts pending the build slot.") No feature code touched. This report is Lanes 1-3.

## Lane 1 — executed results

Base commit: 82b0835c34 (working tree was clean before and after; no feature edits).

### 1a. Unit tests: CarouselSubAgentsTests — PASS, 21/21

Build slot: FIFO ticket queue per fa9cfdf62f, via `build-lock.sh run u4`.
Ticket `000023-u4` (seq 23, pid 66350). Acquired 15:13:01, released 15:31:22.
Slot was FREE, queue empty at acquire time.

Exact command (includes -derivedDataPath per d798c8fbe2):

```
./scripts/carousel-gates/build-lock.sh run u4 -- xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux-unit \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-u4-local-verify \
  -only-testing:cmuxTests/CarouselSubAgentsTests \
  test
```

Full log: /tmp/u4-local-verify-unit.log
xcresult: /tmp/cmux-u4-local-verify/Logs/Test/Test-cmux-unit-2026.09.03_15-13-56-+0200.xcresult

Result: `✔ Test run with 21 tests in 1 suite passed` + `** TEST SUCCEEDED **`.
Failures: 0. Failure output verbatim: (none — no failures).

Handoff-named fixtures, all passing:
- row-118 negative control: "An override resolves verbatim and is never silently
  replaced" (overrideNeverFallsBack) — passed.
- fortyAgents: "Forty agents scan and count correctly" — passed (sits clear of the
  2 s settle window per the committed fixture).
- two-session isolation: "Scanning session A never lists session B's agents" — passed.
- transcript probe 120 s liveness bound: "A quiet transcript past the max age reads
  unknown, never idle" — passed.

Remaining 17 tests in the suite also passed (see log for the full list).

### 1b. UI tests: CarouselSubAgentsUITests — 4 SKIPPED, 0 failures (documented skip)

Ticket seq 24 (pid 76915). Acquired 15:31:30, released 15:44:21.

Exact command:

```
./scripts/carousel-gates/build-lock.sh run u4 -- xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/cmux-u4-local-verify \
  -only-testing:cmuxUITests/CarouselSubAgentsUITests \
  test
```

Full log: /tmp/u4-local-verify-ui.log
xcresult: /tmp/cmux-u4-local-verify/Logs/Test/Test-cmux-2026.09.03_15-31-48-+0200.xcresult

Result: `Executed 4 tests, with 4 tests skipped and 0 failures` +
`** TEST SUCCEEDED **`.

All 4 cases (testChipShowsRunningCountOnly,
testPopoverListsEveryAgentAndItsNesting, testEmptyRootRendersTheEmptyState,
testExcludedWorkspaceCountAppearsAsABadge) skip with the documented reason,
verbatim:

```
Test skipped - The sub-agents chip is not in this build yet. U4 owns the chip;
under Twin Rails it mounts at the right end of U5's top rail, and that rail
does not exist at this head. These cases run unchanged once it does.
```

This skip names U5's top rail exactly as the commit message describes. Correct,
left as-is. Failure output verbatim: (none — no failures).

### Toolchain

- Xcode 26.4, Build version 17E5179g
- swift-driver 1.148.6, Apple Swift 6.3 (swiftlang-6.3.0.123.5 clang-2100.0.123.102),
  Target: arm64-apple-macosx28.0

### Side note (not U4 scope, no action taken)

`./scripts/lint-pbxproj-test-wiring.sh` flags one file NOT in the cmuxTests
Sources build phase: `ClaudeHookSessionStorePersistenceTests.swift`. Pre-existing,
unrelated to U4; recorded here only. CarouselSubAgentsTests.swift itself is wired
(the lint names no U4 file).

## Lane 2 — record, don't repair

No test failed, so no repair question arose. No compile break either: both suites
built and ran unmodified at 82b0835c34. Zero `local-verify:` code-fix commits exist.

## Lane 3 — reconciliation prep for the server session's return

- HEAD: 82b0835c34 ("feat(carousel): U4 sub-agents chip, popover, liveness, badge")
- `git status --short`: empty (clean) at time of writing, before this report's commit.
- Local-verify commits in U4 feature scope: none. The only commit this session will
  add is this report file itself (prefix `local-verify:`, docs-only).
- Files in Sources/Carousel/SubAgents/, cmuxTests/CarouselSubAgentsTests.swift,
  cmuxUITests/CarouselSubAgentsUITests.swift, docs/subagents-panel-plan.md, CONTRACT:
  untouched.

State as I leave it: U4's committed tests are EXECUTED, not just parse-clean —
21 unit passes + 4 documented UI skips, both `** TEST SUCCEEDED **`, full logs at
/tmp/u4-local-verify-unit.log and /tmp/u4-local-verify-ui.log, DerivedData at
/tmp/cmux-u4-local-verify (slot released, no lock held). If the server session's
uncommitted post-11:17 diff touches U4 scope, that diff WINS on conflict; this
report is input to that reconciliation, not a competing branch.
