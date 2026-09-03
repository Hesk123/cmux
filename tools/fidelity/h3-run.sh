#!/usr/bin/env bash
# Modified 2026-09-03 for the cmux carousel build (cmux-carousel-ui CONTRACT, harness H3; row 122).
#
# H3's runner. XCUITest needs UI-test Automation/Accessibility permission, which CANNOT
# be granted non-interactively over ssh: the runner reports
#   "Timed out while enabling automation mode"
# and the whole suite dies. That is a PERMISSION state, not a test result.
#
# THE RULE THIS SCRIPT EXISTS TO ENFORCE: report BLOCKED-ON-PERMISSION, never FAIL and
# never a silent skip.
#
# Reporting it as FAIL is worse than useless -- it puts a red mark against a unit for
# something no unit did and nothing in the repo can fix, and the predictable response is
# to start ignoring red. A silent skip is worse still: the row reads green having tested
# nothing, which is the vacuous-green shape this whole harness is built against.
#
#   h3-run.sh <scheme> <derived-data> [extra xcodebuild args...]
#   h3-run.sh --classify <log>     classify an existing log without running anything
#
# --classify exists so the three outcomes are DIRECTLY testable. Without it the only way
# to exercise the blocked path is to actually hit the permission wall, and a classifier
# nobody can test is one nobody can trust.
#
# Exit codes:  0 pass   ·   1 real test failure   ·   77 BLOCKED-ON-PERMISSION
set -uo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

PERMISSION_RE="Timed out while enabling automation mode|Failed to get automation session|UI Testing Failure - Timed out (registering|while enabling)|The test runner (failed to initialize|encountered an error).*automation"

if [ "${1:-}" = "--classify" ]; then
  LOG=${2:?usage: h3-run.sh --classify <log>}
  [ -f "$LOG" ] || { echo "no such log: $LOG" >&2; exit 2; }
  RC=${3:-1}
else
  SCHEME=${1:?usage: h3-run.sh <scheme> <derived-data> [args...]}
  DD=${2:?derived data path}
  shift 2
  LOG=$(mktemp)
  # The build lock owns serialization; this script only runs the tests.
  xcodebuild test -project cmux.xcodeproj -scheme "$SCHEME" -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$DD" "$@" > "$LOG" 2>&1
  RC=$?
fi

# The signatures that mean "permission", not "broken". Matched before the exit status is
# interpreted, because the runner exits non-zero either way and the status alone cannot
# tell a denied permission from a failing assertion.
if grep -qE "$PERMISSION_RE" "$LOG"; then
  cat >&2 <<MSG
H3 BLOCKED-ON-PERMISSION -- this is NOT a test failure and NOT a pass.

  The XCUITest runner could not enter automation mode. That permission cannot be granted
  non-interactively over ssh; it needs one click in a GUI session on the Mac:

    System Settings -> Privacy & Security -> Automation
      enable the entry for the test runner (cmuxUITests-Runner) under the terminal or
      Xcode process that launches it
    System Settings -> Privacy & Security -> Accessibility
      enable the same process, which XCUITest also requires to synthesise events

  Until then every H3 row for every unit is blocked. Units keep WRITING their XCUITests
  and prove them by the unit-scheme run (cmuxTests) plus the H1, H2 and H4 instruments.

  Reported as BLOCKED, deliberately. A FAIL would put a red mark against a unit for
  something no unit did and nothing in the repo can fix, and a skip would let the row
  read green having tested nothing.

  log: $LOG
MSG
  exit 77
fi

EXECUTED=$("$REPO_ROOT/scripts/carousel-gates/executed-test-count.sh" parse "$LOG" 2>/dev/null || echo 0)
echo "H3 executed tests: $EXECUTED"
if [ "$RC" -eq 0 ]; then
  echo "H3: PASS"
  exit 0
fi
echo "H3: FAIL (xcodebuild exit $RC) -- a real test failure, not a permission state" >&2
grep -E "error:|failed" "$LOG" | tail -15 >&2
exit 1
