#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT row 110).
#
# Row 110: strict concurrency introduces NO NEW WARNING IN ANY CHANGED FILE.
# Pass is zero new warnings in changed files. Pre-existing upstream warnings in
# untouched files are the stated exemption and are reported by count.
#
#   strict-concurrency-gate.sh baseline <out.txt>   build at the pinned sha, save warnings
#   strict-concurrency-gate.sh branch   <out.txt>   build on this branch, save warnings
#   strict-concurrency-gate.sh diff <baseline.txt> <branch.txt> <base-sha>
#   strict-concurrency-gate.sh exemption <build.raw>   assert the ONE upstream error
#                                                      is still present
#
# BASELINE PARTIALITY -- read before trusting a green from `diff`.
# The provisioned baseline (PROVISION-baseline-warnings.txt) is PARTIAL: under
# SWIFT_STRICT_CONCURRENCY=complete the build fails on a hard error in
# Sources/Panels/BrowserWebAuthnSupport.swift, and Swift's batch-mode compilation
# aborts the whole batch, so files the batch never reached emitted no diagnostics.
# A changed file that is absent from the baseline therefore proves nothing: its
# warnings look "new" whether they are new or merely unmeasured.
#
# THE SINGLE EXEMPTION, AND WHY IT IS ASSERTED PRESENT RATHER THAN JUST TOLERATED.
# Under complete strict concurrency the build stops on ONE upstream error:
#   Sources/Panels/BrowserWebAuthnSupport.swift ... does not conform to protocol
#   'WKScriptMessageHandlerWithReply'
# WebKit's reply closure gains @escaping @MainActor @Sendable under strict mode and the
# existing signature no longer satisfies it. That is upstream's, not this build's, and it
# is the only error this gate tolerates.
#
# It is tolerated ONLY while it still exists. `exemption` asserts the error is PRESENT
# and FAILS if it has gone. That looks backwards and is not: an exemption that outlives
# its cause is how a gate quietly stops gating. If upstream fixes that conformance, the
# strict build no longer aborts, the baseline stops being partial, and this whole
# carve-out must be deleted rather than left standing as a permanent hole nobody
# re-examines. Failing loudly is what forces that re-examination.
#
# The build is run WARNINGS-ONLY in the sense that matters here: no
# -warnings-as-errors is added, warnings are harvested from the log even though the
# build exits non-zero, and the exit status of the build is deliberately NOT the gate.
#
# This gate refuses to launder that into either verdict. A changed file with no
# baseline coverage is reported as UNKNOWN-BASELINE and FAILS the gate, because a
# gate that cannot see a file must not pass it. Clearing it means either fixing the
# blocking error so the baseline is complete, or naming the file as an explicit,
# reasoned exemption in the Phase 6 report.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
XCCONFIG="$REPO_ROOT/scripts/carousel-gates/strict-concurrency.xcconfig"
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.cargo/bin:$PATH"

build_warnings() {
  local tag=$1 out=$2
  cd "$REPO_ROOT"
  # Row 133 / AGENTS.md is binding: NEVER a bare `xcodebuild`. An untagged build shares
  # the default debug socket and bundle id with every other agent on this Mac. An
  # earlier revision of this gate called xcodebuild directly, which its own sweep
  # caught -- recorded here rather than quietly corrected.
  #
  # reload.sh takes no --xcconfig flag, and adding one would mean editing a 2056-line
  # script all seven units share. XCODE_XCCONFIG_FILE is Xcode's own documented
  # environment override and applies the settings file to the build with no command
  # line flag at all, so row 110's "injected by xcconfig" and row 133's "always the
  # tagged path" are both satisfied without touching a shared script.
  #
  # --no-launch is deliberate: this is a measurement build and must not steal focus.
  "$REPO_ROOT/scripts/carousel-gates/build-lock.sh" with strict-concurrency-gate "$REPO_ROOT" "$tag" -- \
    env XCODE_XCCONFIG_FILE="$XCCONFIG" ./scripts/reload.sh --tag "$tag" \
      2>&1 | tee "$out.raw" | grep -E "warning:|error:" | sort -u > "$out" || true
  echo "wrote $out ($(wc -l < "$out" | tr -d ' ') diagnostic lines) via the tagged path, tag=$tag"
}

# A diagnostic line is "<path>:<line>:<col>: warning: <text>". Normalize to
# "<repo-relative path>|<text>" so a line-number shift in an untouched region does
# not read as a new warning -- that would make the gate fire on formatting.
normalize() {
  sed -E 's#^'"$REPO_ROOT"'/##' "$1" \
    | sed -E 's#^([^:]+):[0-9]+:[0-9]+: (warning|error): #\1|\2: #' \
    | sort -u
}

# The one tolerated upstream error, matched on file plus protocol so a DIFFERENT error
# in the same file cannot pass as this one.
EXEMPT_FILE='Sources/Panels/BrowserWebAuthnSupport.swift'
EXEMPT_PROTOCOL='WKScriptMessageHandlerWithReply'

check_exemption() {
  local raw=${1:?usage: exemption <build.raw>}
  [ -f "$raw" ] || { echo "no such build log: $raw" >&2; return 2; }
  local errors exempt other
  errors=$(grep -E ' error: ' "$raw" | sort -u || true)
  exempt=$(printf '%s\n' "$errors" | grep -F "$EXEMPT_FILE" | grep -F "$EXEMPT_PROTOCOL" || true)
  other=$(printf '%s\n' "$errors" | grep -v -F "$EXEMPT_FILE" | grep -v '^$' || true)

  if [ -z "$exempt" ]; then
    echo "ROW 110 EXEMPTION: FAIL -- the tolerated upstream error is GONE."
    echo "  Expected in $EXEMPT_FILE: conformance to $EXEMPT_PROTOCOL."
    echo "  If upstream fixed it, the strict build no longer aborts, the warning baseline"
    echo "  is no longer partial, and this exemption must be DELETED rather than left"
    echo "  standing. An exemption that outlives its cause is a hole nobody re-examines."
    return 1
  fi
  echo "ROW 110 EXEMPTION: present, as required"
  printf '%s\n' "$exempt" | sed 's/^/  /'
  if [ -n "$other" ]; then
    echo "ROW 110 EXEMPTION: FAIL -- error(s) beyond the single tolerated one:"
    printf '%s\n' "$other" | sed 's/^/  /'
    return 1
  fi
  echo "ROW 110 EXEMPTION: PASS -- exactly one error, and it is the stated upstream one"
  return 0
}

case "${1:?usage: baseline|branch|diff|exemption}" in
  exemption) shift; check_exemption "$@" ;;
  baseline) build_warnings "${CMUX_STRICT_TAG:-strict-baseline}" "${2:?out file}" ;;
  branch)   build_warnings "${CMUX_STRICT_TAG:-strict-branch}" "${2:?out file}" ;;
  diff)
    BASE=${2:?baseline file}; BRANCH=${3:?branch file}; BASE_SHA=${4:?base sha}
    cd "$REPO_ROOT"
    CHANGED=$(git diff --name-only "$BASE_SHA"...HEAD -- '*.swift' | sort -u)
    if [ -z "$CHANGED" ]; then echo "no changed .swift files vs $BASE_SHA -- gate vacuous, and said so"; exit 0; fi
    normalize "$BASE" > /tmp/.sc-base.$$
    normalize "$BRANCH" > /tmp/.sc-branch.$$
    trap 'rm -f /tmp/.sc-base.$$ /tmp/.sc-branch.$$' EXIT

    new_total=0; unknown=0
    echo "changed .swift files vs $BASE_SHA:"; echo "$CHANGED" | sed 's/^/  /'
    echo
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      base_n=$(grep -c "^$f|" /tmp/.sc-base.$$ || true)
      raw_base_seen=$(grep -c "^$f|" /tmp/.sc-base.$$ || true)
      if ! grep -q "^$f|" /tmp/.sc-base.$$ && ! grep -q "^$f\$" <<< "$(cut -d'|' -f1 /tmp/.sc-base.$$ | sort -u)"; then
        # No diagnostics AND no evidence the baseline build ever reached this file.
        echo "UNKNOWN-BASELINE  $f  (absent from a partial baseline; see the header)"
        unknown=$((unknown + 1))
      fi
      newlines=$(comm -13 <(grep "^$f|" /tmp/.sc-base.$$ | sort -u) <(grep "^$f|" /tmp/.sc-branch.$$ | sort -u) || true)
      if [ -n "$newlines" ]; then
        n=$(printf '%s\n' "$newlines" | grep -c . || true)
        new_total=$((new_total + n))
        echo "NEW ($n)  $f"; printf '%s\n' "$newlines" | sed 's/^/    /'
      fi
    done <<< "$CHANGED"

    untouched=$(comm -13 <(cut -d'|' -f1 /tmp/.sc-base.$$ | sort -u | grep -F -x -f <(echo "$CHANGED") || true) \
                         <(cut -d'|' -f1 /tmp/.sc-base.$$ | sort -u) | wc -l | tr -d ' ')
    echo
    echo "STATED EXEMPTION: pre-existing strict-concurrency diagnostics in untouched files: $(wc -l < /tmp/.sc-base.$$ | tr -d ' ') lines across ~$untouched files. Not this build's to fix."
    echo "new warnings in changed files: $new_total"
    echo "changed files with no baseline coverage: $unknown"
    if [ "$new_total" -eq 0 ] && [ "$unknown" -eq 0 ]; then
      echo "ROW 110: PASS"; exit 0
    fi
    echo "ROW 110: FAIL"; exit 1
    ;;
  *) sed -n '2,30p' "$0"; exit 2 ;;
esac
