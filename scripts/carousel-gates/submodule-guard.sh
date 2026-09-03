#!/usr/bin/env bash
# Modified 2026-09-03 for the cmux carousel build (cmux-carousel-ui; integration checks).
#
# Two INDEPENDENT invariants on the submodule paths. Both are needed, and the reason is
# worth stating because the obvious one does not catch the reported hazard.
#
#   A. POINTERS UNCHANGED -- `git diff <base> -- ghostty vendor/bonsplit` is empty.
#      Catches a unit that committed a moved submodule SHA, which silently changes what
#      everyone downstream builds against.
#
#   B. WORKING-TREE SHAPE INTACT -- neither path is a SYMLINK, and `git status` succeeds.
#      This is the one that catches what was actually reported. A worktree with
#      `ghostty` symlinked makes EVERY git command fail with
#        "expected submodule path 'ghostty' not to be a symbolic link"
#      while the committed pointer is untouched. Check A therefore PASSES on a worktree
#      that is completely broken -- measured, not assumed: at the time this was written
#      cmux-u1, cmux-u2, cmux-u6 and cmux-spike all had symlinked paths and a failing
#      `git status`, and all four had identical pointers to the base.
#
#   submodule-guard.sh <base-sha> [worktree]     check one worktree (default: this one)
#   submodule-guard.sh --survey <base-sha>       check every ~/code/cmux* worktree
set -uo pipefail
PATHS=(ghostty vendor/bonsplit)

check_one() {
  local base=$1 wt=${2:-.} fail=0 p
  echo "== $(basename "$(cd "$wt" && pwd)")"

  # A. pointers -- TREE TO TREE, never against the working tree.
  # `git diff <base> -- <submodule>` includes WORKING-TREE state, so a submodule with
  # dirty or uninitialised content reports as a moved pointer when the committed SHA is
  # identical. That is not hypothetical: an earlier revision of this script flagged
  # cmux-critic-u2 as POINTER MOVED, and comparing the trees showed both SHAs equal.
  # A guard that sends someone chasing a pointer that never moved is worse than none.
  local diff
  diff=$(git -C "$wt" diff "$base" HEAD -- "${PATHS[@]}" 2>/dev/null)
  if [ -n "$diff" ]; then
    echo "  POINTER MOVED vs $base:"
    git -C "$wt" ls-tree "$base" "${PATHS[@]}" 2>/dev/null | sed 's/^/    base: /'
    git -C "$wt" ls-tree HEAD "${PATHS[@]}" 2>/dev/null | sed 's/^/    HEAD: /'
    fail=1
  else
    echo "  pointers: unchanged vs $base"
  fi

  # B. working-tree shape -- the check that actually catches the reported hazard
  for p in "${PATHS[@]}"; do
    if [ -L "$wt/$p" ]; then
      echo "  SYMLINKED: $p -> $(readlink "$wt/$p")"
      echo "    Every git command in this worktree fails with \"expected submodule path"
      echo "    '$p' not to be a symbolic link\", so status, diff and commit are all broken."
      fail=1
    elif [ ! -e "$wt/$p" ]; then
      echo "  MISSING: $p"
      fail=1
    fi
  done

  local st
  st=$(git -C "$wt" status --short 2>&1 >/dev/null)
  if [ -n "$st" ]; then
    echo "  git status FAILS: $(printf '%s' "$st" | head -1)"
    fail=1
  fi

  if [ "$fail" -eq 0 ]; then
    echo "  SUBMODULE GUARD: PASS"
  else
    echo "  SUBMODULE GUARD: FAIL"
    echo "    Remedy, from tools/fidelity/README.md -- ghostty must be an EMPTY REAL"
    echo "    DIRECTORY (a symlink breaks git), and vendor/bonsplit a COPY with its nested"
    echo "    .git removed (without it the build dies on a missing package manifest):"
    echo "      rm -rf ghostty && mkdir ghostty"
    echo "      ln -sfn /Users/dawid/code/cmux/GhosttyKit.xcframework GhosttyKit.xcframework"
    echo "      cp -R /Users/dawid/code/cmux/vendor/bonsplit/ vendor/bonsplit/"
    echo "      rm -rf vendor/bonsplit/.git"
  fi
  return $fail
}

if [ "${1:-}" = "--survey" ]; then
  base=${2:?usage: --survey <base-sha>}
  rc=0
  for w in "$HOME"/code/cmux "$HOME"/code/cmux-*; do
    [ -d "$w/.git" ] || [ -f "$w/.git" ] || continue
    check_one "$base" "$w" || rc=1
  done
  exit $rc
fi
check_one "${1:?usage: submodule-guard.sh <base-sha> [worktree]}" "${2:-.}"
