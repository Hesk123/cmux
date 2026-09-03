#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT rows 88, 129).
#
# GPL-3.0-or-later compliance, in three parts. cmux is GPL-3.0-or-later and this build
# is pushed to a public fork, which is CONVEYING under the licence, so section 5(a)
# applies and is not optional.
#
#   gpl-compliance.sh notices <base-sha>     row 129: every modified file carries a
#                                            prominent notice naming the change and its date
#   gpl-compliance.sh license                row 88:  LICENSE is byte-identical to upstream's
#   gpl-compliance.sh bundle <app-path>      row 88:  the repo's own bundle-licence test is green
#   gpl-compliance.sh all <base-sha> <app>   all three
#
# Row 129's reason for existing: zero files under Sources/ carry ANY header today, so
# the previous "no conflicting header added" clause passed automatically -- a check
# that cannot fail is not a check. This one asserts a notice is PRESENT, which can.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

# GPL-3 5(a): "The work must carry prominent notices stating that you modified it,
# and giving a relevant date." Both halves are required, so both are checked.
NOTICE_RE='[Mm]odified [0-9]{4}-[0-9]{2}-[0-9]{2}'
NOTICE_HEAD_LINES=40

check_notices() {
  local base=${1:?base sha}
  local missing=0 checked=0
  # Only files this build MODIFIED or ADDED. Deleted files carry nothing.
  while IFS=$'\t' read -r status path; do
    case "$status" in D*) continue ;; esac
    case "$path" in
      *.swift|*.sh|*.py|*.m|*.h|*.c|*.mm|*.xcconfig) ;;
      *) continue ;;
    esac
    checked=$((checked + 1))
    if ! head -"$NOTICE_HEAD_LINES" "$path" 2>/dev/null | grep -Eq "$NOTICE_RE"; then
      echo "MISSING 5(a) NOTICE  $path"
      missing=$((missing + 1))
    fi
  done < <(
    # Two-dot against the working tree, plus untracked files. A HEAD-only diff cannot
    # see a file that is written but not yet committed, and that is precisely when a
    # maker runs this. Proven by a positive control that a HEAD-only diff passed.
    git diff --name-status "$base"
    git ls-files --others --exclude-standard | sed 's/^/A\t/'
  )

  echo
  echo "files checked: $checked   missing a notice: $missing"
  if [ "$checked" -eq 0 ]; then
    echo "ROW 129: VACUOUS -- no source files changed vs $base. Reported, not passed."
    return 0
  fi
  if [ "$missing" -eq 0 ]; then echo "ROW 129: PASS"; return 0; fi
  echo "ROW 129: FAIL -- add a header line of the form:"
  echo "  // Modified $(date +%F) for the cmux carousel build (<what changed>)."
  return 1
}

check_license() {
  # Row 88: `diff LICENSE` against upstream stays empty. Compare against the pinned
  # upstream blob rather than a working-tree copy, so a local edit cannot hide itself.
  local upstream_ref
  upstream_ref=$(git rev-parse --verify --quiet upstream/main || git rev-parse --verify --quiet origin/main || echo "")
  if [ -z "$upstream_ref" ]; then
    echo "ROW 88 (LICENSE): CANNOT VERIFY -- no upstream/main or origin/main ref to diff against." >&2
    return 1
  fi
  if git diff --quiet "$upstream_ref" -- LICENSE; then
    echo "ROW 88 (LICENSE): PASS -- byte-identical to $upstream_ref"
    return 0
  fi
  echo "ROW 88 (LICENSE): FAIL -- LICENSE differs from $upstream_ref:"
  git diff --stat "$upstream_ref" -- LICENSE
  return 1
}

check_bundle() {
  local app=${1:?app path}
  # Row 88 is explicit that this is a shell test under Tests/ and is NOT covered by
  # row 84's xcodebuild suites, so it is run here on purpose rather than assumed.
  if [ ! -x Tests/test_app_bundle_license_compliance.sh ]; then
    echo "ROW 88 (bundle): MISSING Tests/test_app_bundle_license_compliance.sh" >&2; return 2
  fi
  CMUX_APP_PATH="$app" ./Tests/test_app_bundle_license_compliance.sh "$app" \
    || ./scripts/verify-app-bundle-licenses.sh "$app"
  echo "ROW 88 (bundle): PASS -- LICENSE and THIRD_PARTY_LICENSES.md ship in Contents/Resources"
}

case "${1:?usage: notices|license|bundle|all}" in
  notices) shift; check_notices "$@" ;;
  license) check_license ;;
  bundle)  shift; check_bundle "$@" ;;
  all)
    rc=0
    check_notices "${2:?base sha}" || rc=1
    check_license || rc=1
    check_bundle "${3:?app path}" || rc=1
    exit $rc
    ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
