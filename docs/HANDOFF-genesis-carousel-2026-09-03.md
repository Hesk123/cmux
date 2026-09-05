# HANDOFF — Genesis carousel, full build (2026-09-03)

**To:** OC | Local U4 session (Mac, opencode). **From:** Hive orchestrator (Mac).
**Scope change:** you are no longer verify-only. The Hetzner server (`hive-brain`) that ran the primary carousel session was **permanently terminated today** — there is no server session left to collide with. The earlier "don't double server work / U4 verify only" boundary is **LIFTED**. You now own the **full carousel build**, and a new task: rename the product to **Genesis**.

## Current build stage (verified 2026-09-03, do not re-derive)

The carousel is a card-based agent-switching UI for cmux: track + card geometry (U1), motion layer (U2), prompt bar + chip + focus/pty routing (U3), sub-agents chip + popover + liveness + badge (U4), Twin Rails top bar + Hive bridge + statusline tee (U5), grid + toast + overlay motion (U6), harness + gates + recorder + data seam (U7).

- **Branch `carousel/integration` (HEAD 53096e7a9b) = the assembled product.** All 7 units are MERGED (U1 d6e5d74629, U2 002132c506, U3 54d5d9b422, U4 9dd6909393, U5 12130678c3, U6 4a4c38840e, U7 a4a1bb400a) plus critic rounds (U1 d2fe237634, U3 0ba0ece75e, U5 e93162b8dc) and row-129 notice wording (53096e7a9b). Working tree clean. **This is where full-carousel work and the Genesis rename happen.**
- **Branch `carousel/u4` (HEAD 786dd7bf8a) = your unit.** U4 chip/popover/liveness/badge committed at 82b0835c34. Tests EXECUTED (see docs/u4-local-verify-2026-09-03.md): 21/21 unit PASS; 4 UI tests SKIPPED only because U5's Twin Rails top rail (where the U4 chip mounts) does not exist on this branch head. Those 4 run unchanged where the rail exists — i.e. on carousel/integration.

## Next work (build continuation, in priority order)

1. **Run the 4 U4 UI tests on `carousel/integration`, where U5's Twin Rails rail exists.** They are `testChipShowsRunningCountOnly`, `testPopoverListsEveryAgentAndItsNesting`, `testEmptyRootRendersTheEmptyState`, `testExcludedWorkspaceCountAppearsAsABadge` in cmuxUITests/CarouselSubAgentsUITests.swift. On u4 they skip with a message naming U5's top rail; on integration the chip should mount at the right end of the top rail and these must now PASS (or reveal real mount bugs to fix). This is the concrete unfinished seam.
2. **Full-carousel dogfood** on carousel/integration: tagged build, exercise track, prompt bar, Twin Rails top bar, grid, sub-agents chip+popover, motion. Follow the cmux dogfood + notify handoff pattern in CLAUDE.md.
3. **Resolve any gate/critic findings** surfaced by the U7 harness/gates on integration.

## Genesis rename workstream (product cmux -> Genesis)

Goal: the app is named **Genesis**, matching Dawid's ecosystem. Scope carefully; do this on carousel/integration (or a branch off it), and use the cmux-localization skill (localization audit + BOTH web message catalogs) for every user-facing string.

Known touch points (grep to complete, do not assume this is exhaustive):
- `cmux.xcodeproj/project.pbxproj`: release-config `PRODUCT_NAME = cmux;` (approx lines 13462, 13482) -> `Genesis`. DEV config is `PRODUCT_NAME = "cmux DEV"` -> decide `Genesis DEV`.
- `Resources/Info.plist`: `CFBundleDisplayName` and `CFBundleName` already use `$(PRODUCT_NAME)`, so they follow automatically; the "New $(PRODUCT_NAME) Workspace/Window Here" menu strings also follow.
- `Resources/Localizable.xcstrings`: user-facing literal "cmux" values -> "Genesis" (localization audit required, en + ja + web/messages/en.json + web/messages/ja.json).
- **Do NOT blindly change bundle identifiers, socket names, or the reload.sh `--tag` mechanics** — those are dev-infra that gate signing, iPhone pairing, and multi-agent isolation (see CLAUDE.md). Change the DISPLAY/product name and user-facing strings first; only touch bundle IDs if Dawid explicitly wants a full identifier rebrand, and treat that as its own reviewed change.

## Rules you MUST obey (from cmux CLAUDE.md)

- **Tagged builds only.** Never bare `xcodebuild` or `open` an untagged app. Use `./scripts/reload.sh --tag <slug>` (add `--launch` to run). Report builds as a markdown link to `http://127.0.0.1:17320/<tag>`, never a file:// or /tmp path.
- **Build-lock FIFO + `-derivedDataPath` always** (per carousel gate scripts/carousel-gates/build-lock.sh; see the u4 verify report for the exact invocation pattern).
- **Test wiring:** a new `.swift` in cmuxTests/ needs its PBXFileReference + Sources build-phase entry or it is silently skipped; run `./scripts/lint-pbxproj-test-wiring.sh`.
- **Localization audit** for any UI/menu/settings string change; state what was audited in the handoff.
- **Regression bugs = two commits** (failing test first, then fix).
- **First pass, then dogfood; notify via `cmux notify`.** Do not launch background review agents by default. Merging UI/runtime changes needs Dawid's explicit approval after dogfood.
- **Submodule safety** for any ghostty change; never commit on detached HEAD.

## Guardrails

- Whole-carousel + rename work: `carousel/integration` (or a branch off it). U4-specific fixes: `carousel/u4`, then merge to integration.
- No force-push, no history rewrite on shared carousel branches.
- The old server is gone; GitHub `claude-config` (~/.claude) is frozen since April and `life` synced only through ~08:00 today — so THIS repo on the Mac is now the source of truth for the carousel. Commit your work; it is no longer mirrored by the server.

## Start here

Read docs/subagents-panel-plan.md (U4 data source + panel design) and docs/u4-local-verify-2026-09-03.md (what already passed), then switch to the carousel/integration worktree at /Users/dawid/code/cmux-integration and execute step 1 (run the 4 U4 UI tests where the Twin Rails rail exists).

---
End of file. Return confirmation with the path.
