#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT row 118).
#
# Row 118: ONE injectable path provider, overridable by CMUX_CAROUSEL_DATA_ROOT. No
# read in this build's diff may reach the user's real home directory by any route.
#
# A probe on the Mac proved both Swift home-directory APIs IGNORE a HOME override, so
# a temp-HOME test seam does not work and the provider is the only seam there is.
#
# The ban list is deliberately NOT just the two API names. Sources/ holds ~109 uses of
# them, and one is SidebarPathFormatter.homeDirectoryPath -- a `static let` that a new
# file can read in a single expression, containing NEITHER banned name, and defeating
# the seam entirely. Rule 37's reuse ladder makes reaching for that existing helper the
# LIKELY path, not the unlucky one. So every existing cmux home-path helper is on the
# list, enumerated once from that grep and committed here beside the check.
#
#   data-root-seam-check.sh <base-sha>
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
BASE=${1:?usage: data-root-seam-check.sh <base-sha>}

# --- the ban list -------------------------------------------------------------
# 1. The two Foundation APIs row 118 names.
# 2. Every cmux home-path helper found by enumerating the Sources/ grep, so a
#    reuse of an existing helper cannot slip past a name-only check.
BANNED=(
  'FileManager\.default\.homeDirectoryForCurrentUser'
  'NSHomeDirectory\(\)'
  'homeDirectoryForCurrentUser'
  'SidebarPathFormatter\.homeDirectoryPath'
  'URL\.homeDirectory'
  'ProcessInfo\.processInfo\.environment\["HOME"\]'
  'getenv\("HOME"\)'
)

echo "row 118 seam check, diff vs $BASE"
echo "ban list:"; printf '  %s\n' "${BANNED[@]}"; echo

# The check covers the ENTIRE diff, not the paths it happens to name. Added lines
# only: a banned call that already existed in an untouched region is upstream's.
# The provider is the one file allowed to resolve a home directory, and it is
# allowlisted BY PATH with a cap on how many times. A blanket ban with nowhere
# legitimate to resolve a default is a ban that gets worked around rather than
# followed -- someone reaches for SidebarPathFormatter.homeDirectoryPath instead and
# the seam is gone with no banned name anywhere in the diff.
ALLOWLIST_FILE='Sources/Carousel/Data/CarouselDataRoot.swift'
ALLOWLIST_MAX=1
# Two-dot against the WORKING TREE, not "$BASE...HEAD".
# A positive control caught this: a file with a banned call, staged but not yet
# committed, was invisible to a HEAD-only diff and the gate returned PASS. A maker
# runs this before committing, which is exactly when the gate must be able to see the
# violation, so the comparison covers the index and the working tree too.
DIFF=$(git diff -U0 "$BASE" -- '*.swift' ":(exclude)$ALLOWLIST_FILE" | grep -E '^\+' | grep -v '^+++' || true)

# Untracked files are in no diff at all. A new Swift file that has never been `git
# add`ed would slip past every check here, so it is named rather than ignored.
UNTRACKED=$(git ls-files --others --exclude-standard -- '*.swift' | grep -v "^$ALLOWLIST_FILE$" || true)
if [ -n "$UNTRACKED" ]; then
  echo "UNTRACKED Swift files -- not in any diff, so not covered by the ban below:"
  printf '%s\n' "$UNTRACKED" | sed 's/^/  /'
  echo "  git add them, or this gate is blind to them."
  echo
fi
if [ -z "$DIFF" ] && [ -z "$UNTRACKED" ]; then
  echo "no added Swift lines vs $BASE -- check vacuous, and said so."
  exit 0
fi

hits=0
[ -n "$UNTRACKED" ] && hits=$((hits + 1))
for pat in "${BANNED[@]}"; do
  found=$(printf '%s\n' "$DIFF" | grep -E "$pat" || true)
  if [ -n "$found" ]; then
    echo "BANNED: $pat"
    printf '%s\n' "$found" | sed 's/^/    /'
    hits=$((hits + 1))
  fi
done

# The provider must actually exist and must actually read the env var, or the ban
# passes while there is nothing to use instead.
PROVIDER=Sources/Carousel/Data/CarouselDataRoot.swift
if [ ! -f "$PROVIDER" ]; then
  echo "MISSING PROVIDER: $PROVIDER does not exist. The ban has no replacement to point at."
  hits=$((hits + 1))
elif ! grep -q 'CMUX_CAROUSEL_DATA_ROOT' "$PROVIDER"; then
  echo "PROVIDER DOES NOT READ CMUX_CAROUSEL_DATA_ROOT: $PROVIDER"
  hits=$((hits + 1))
fi

# The allowlist is capped, not open. One resolution is a seam; several is a habit.
if [ -f "$ALLOWLIST_FILE" ]; then
  # Count CODE lines only. A doc comment naming the banned APIs -- which this file
  # has, because it explains why they are banned -- cannot bypass a seam, and counting
  # it would push the next author to delete the explanation to get under the cap.
  allow_uses=$(grep -vE '^[[:space:]]*(//|\*|/\*)' "$ALLOWLIST_FILE" \
                 | grep -Ec 'homeDirectoryForCurrentUser|NSHomeDirectory\(\)' || true)
  echo "allowlisted home-directory resolutions in $ALLOWLIST_FILE: $allow_uses (cap $ALLOWLIST_MAX)"
  if [ "$allow_uses" -gt "$ALLOWLIST_MAX" ]; then
    echo "ALLOWLIST EXCEEDED: $allow_uses uses in the provider, cap is $ALLOWLIST_MAX."
    hits=$((hits + 1))
  fi
fi

echo
if [ "$hits" -eq 0 ]; then echo "ROW 118 (seam): PASS"; exit 0; fi
echo "ROW 118 (seam): FAIL -- $hits violation(s). Read the data root through $PROVIDER."
exit 1
