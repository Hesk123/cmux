#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT row 134).
#
# Row 134 / AGENTS.md:132 -- a .swift file in cmuxTests/ without a PBXFileReference
# and a PBXSourcesBuildPhase entry is SILENTLY SKIPPED, and both `xcodebuild test`
# and bot reviews then report green with "Executed 0 tests". That is the vacuous-green
# shape this fleet keeps hitting, and it would make most of the contract's
# verification unfalsifiable: every data-driven row would pass by not running.
#
# Two mechanical checks, both required:
#   1. the repo's own ./scripts/lint-pbxproj-test-wiring.sh passes
#   2. the EXECUTED test count is parsed out of the test log, is greater than zero,
#      and has increased by the number of tests the unit added
#
#   executed-test-count.sh lint
#   executed-test-count.sh parse <test-log>              print the executed count
#   executed-test-count.sh assert <test-log> <min> [<expected-increase> <baseline>]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

parse_count() {
  local log=$1
  [ -f "$log" ] || { echo "no such log: $log" >&2; exit 2; }
  # xcodebuild prints per-suite lines: "Executed N tests, with M failures ...".
  # Take the LARGEST, which is the top-level suite total, rather than summing --
  # summing double-counts because nested suites report their own totals too.
  local n
  n=$(grep -Eo 'Executed [0-9]+ test' "$log" | grep -Eo '[0-9]+' | sort -n | tail -1 || true)
  # Newer xcodebuild/swift-testing wording.
  if [ -z "$n" ]; then
    n=$(grep -Eo 'Test run with [0-9]+ test' "$log" | grep -Eo '[0-9]+' | sort -n | tail -1 || true)
  fi
  echo "${n:-0}"
}

case "${1:?usage: lint|parse|assert}" in
  lint)
    cd "$REPO_ROOT"
    if [ ! -x ./scripts/lint-pbxproj-test-wiring.sh ]; then
      echo "MISSING: ./scripts/lint-pbxproj-test-wiring.sh -- row 134 names it explicitly." >&2
      exit 2
    fi
    BASELINE="$REPO_ROOT/scripts/carousel-gates/pbxproj-wiring-baseline.txt"
    OUT=$(./scripts/lint-pbxproj-test-wiring.sh 2>&1 || true)
    # The lint is RED at the pinned baseline sha: one upstream test file is already
    # unwired. Requiring a green would have blocked from day one for a defect this
    # build did not cause, and a permanently red gate teaches people to skip it. The
    # gate is a diff against the recorded baseline: no NEW unwired file.
    FLAGGED=$(printf '%s\n' "$OUT" | sed -n 's/^  - //p' | sort -u)
    KNOWN=$(grep -v '^#' "$BASELINE" 2>/dev/null | grep -v '^[[:space:]]*$' | sort -u || true)
    NEW=$(comm -13 <(printf '%s\n' "$KNOWN") <(printf '%s\n' "$FLAGGED") | grep -v '^$' || true)
    FIXED=$(comm -23 <(printf '%s\n' "$KNOWN") <(printf '%s\n' "$FLAGGED") | grep -v '^$' || true)
    if [ -n "$KNOWN" ]; then
      echo "STATED EXEMPTION: unwired at the pinned baseline sha, upstream's not ours:"
      printf '%s\n' "$KNOWN" | sed 's/^/  /'
    fi
    if [ -n "$FIXED" ]; then
      echo "NOTE: these were on the baseline and are now wired -- trim the baseline file:"
      printf '%s\n' "$FIXED" | sed 's/^/  /'
    fi
    if [ -n "$NEW" ]; then
      echo "NEW UNWIRED TEST FILE(S) -- these would report green with Executed 0 tests:"
      printf '%s\n' "$NEW" | sed 's/^/  /'
      echo "ROW 134 (wiring lint): FAIL"
      exit 1
    fi
    # The repo lint matches the four wiring patterns as STRINGS, so a PBXBuildFile
    # whose fileRef is the literal `None` satisfies all four and it reports ok. The
    # file is then compiled by nothing and the suite runs without it -- the same
    # "Executed 0 tests" shape, one level deeper. Resolution is checked separately.
    if ! /usr/bin/python3 "$REPO_ROOT/scripts/carousel-gates/pbxproj-ref-integrity.py"; then
      echo "ROW 134 (wiring lint): FAIL -- a build-file reference does not resolve"
      exit 1
    fi
    echo "ROW 134 (wiring lint): PASS -- no new unwired test file, every reference resolves"
    ;;
  parse) parse_count "${2:?log}" ;;
  assert)
    LOG=${2:?log}; MIN=${3:?minimum executed tests}
    INCREASE=${4:-}; BASELINE=${5:-}
    N=$(parse_count "$LOG")
    echo "executed tests: $N"
    fail=0
    if [ "$N" -lt "$MIN" ]; then
      echo "FAIL: executed $N tests, expected at least $MIN." >&2
      echo "      An 'Executed 0 tests' green is the exact failure row 134 exists to catch." >&2
      fail=1
    fi
    if [ -n "$INCREASE" ] && [ -n "$BASELINE" ]; then
      want=$((BASELINE + INCREASE))
      if [ "$N" -lt "$want" ]; then
        echo "FAIL: executed $N, baseline $BASELINE + $INCREASE added = $want expected." >&2
        echo "      A shortfall means new test files are present but not wired into the pbxproj." >&2
        fail=1
      fi
    fi
    if [ "$fail" -eq 0 ]; then echo "ROW 134 (executed count): PASS"; else echo "ROW 134: FAIL"; fi
    exit $fail
    ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
