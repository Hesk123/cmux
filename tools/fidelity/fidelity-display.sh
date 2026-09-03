#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT row 119).
#
# Sets and restores the fidelity display mode. CONTRACT row 119: "Reaching the mode
# is a named command, not an assumption." D-16 names the built-in panel at its More
# Space scaled mode -- 1920 x 1243 logical, visibleFrame 1920 x 1205, backingScaleFactor
# 2.0 -- because it is the only mode on this machine that both backs at 2x and leaves
# room for a 1344 x 1080 logical window. The default mode is 1710 x 1107 with a
# visibleFrame of 1710 x 1073, seven logical pixels short of 1080.
#
# The virtual-display route is NOT used: scripts/create-virtual-display.m hardcodes
# hiDPI = 0 and provisioning measured backingScaleFactor 1.0 from it.
#
#   fidelity-display.sh set        switch to the More Space fidelity mode
#   fidelity-display.sh restore    switch back to the machine's default mode
#   fidelity-display.sh check [app]  run the precondition assertions (exit 1 on failure).
#                                    With an app-name substring it ALSO asserts that
#                                    app's window is exactly 1344 x 1080 -- the check
#                                    that catches a silently CLAMPED window, which the
#                                    Phase 0 spike lost a run to at 1670 x 1033.
#   fidelity-display.sh report     print the current display state, always exit 0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# Persistent screen id of the built-in panel on this machine, from `displayplacer list`.
# Machine-specific: re-read it with `displayplacer list` if this ever runs elsewhere.
SCREEN_ID="${CMUX_FIDELITY_SCREEN_ID:-37D8832A-2D66-02CA-B9F7-8F30A301B230}"
FIDELITY_MODE="res:1920x1243 hz:60 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0"
DEFAULT_MODE="res:1710x1107 hz:60 color_depth:8 enabled:true scaling:on origin:(0,0) degree:0"

BIN="${TMPDIR:-/tmp}/cmux-display-precondition"

ensure_bin() {
  local src="$SCRIPT_DIR/DisplayPrecondition.swift"
  if [ ! -x "$BIN" ] || [ "$src" -nt "$BIN" ]; then
    swiftc -O -parse-as-library -o "$BIN" "$src" 2>&1 | grep -v '^remark:' || true
  fi
  [ -x "$BIN" ] || { echo "could not build $BIN from $src" >&2; exit 2; }
}

case "${1:-check}" in
  set)
    command -v displayplacer >/dev/null || { echo "displayplacer not installed (brew install displayplacer)" >&2; exit 2; }
    displayplacer "id:$SCREEN_ID $FIDELITY_MODE"
    sleep 1
    ensure_bin
    if [ -n "${2:-}" ]; then "$BIN" --window "$2"; else "$BIN"; fi
    ;;
  restore)
    command -v displayplacer >/dev/null || { echo "displayplacer not installed" >&2; exit 2; }
    displayplacer "id:$SCREEN_ID $DEFAULT_MODE"
    echo "restored to the default 1710x1107 mode"
    ;;
  check)
    ensure_bin
    # Never fall back to ratio-only assertions silently. Aborting is the point: about
    # twenty-five absolute-pixel rows would otherwise void by exemption and a report
    # full of silent exemptions reads like a pass.
    if [ -n "${2:-}" ]; then "$BIN" --window "$2"; else "$BIN"; fi
    ;;
  report)
    ensure_bin; "$BIN" --report
    ;;
  *)
    sed -n '2,20p' "$0"; exit 2
    ;;
esac
