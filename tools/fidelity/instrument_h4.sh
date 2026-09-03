#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT rows 112, 128).
#
# H4 -- the ONLY admissible proof of frame rate.
#
# H2 reads frame timestamps out of a screen recording and will happily report 60 fps
# while the app drops frames the compositor papers over. CONTRACT row 112 rules that
# inadmissible and names Instruments as the proof, because committed frame time and
# hitching are properties of the render server, not of a capture.
#
# What it records: Core Animation and SwiftUI, attached to the running tagged app,
# through a switch, a grid toggle and a five-press burst.
#
# What it is measured against: the ROW-128 RELEASE configuration, on the D-16 surface
# (built-in panel, More Space scaled mode, backingScaleFactor 2.0). The reason is real
# scanout -- frame delivery and hitching are properties of a display actually driving a
# panel at its refresh rate, which a synthetic or offscreen surface does not reproduce.
# That is a DIFFERENT question from where the pixels are, which is what H1 asserts, and
# keeping the two reasons apart means H4 stays on the panel even if fidelity capture
# ever moves.
#
# Pass (row 112): no hitch exceeding 100 ms AND at most 1 % of frames over budget.
# The bar is 60 fps because the target panel is 60 Hz -- a MacBook Air M3 15" with no
# ProMotion. The threshold is READ FROM THE DISPLAY AT RUNTIME rather than hardcoded,
# so the gate stays correct if this ever runs on a 120 Hz panel.
#
#   instrument_h4.sh record <tag> <out.trace>     attach and record
#   instrument_h4.sh analyse <out.trace>          apply the row-112 thresholds
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MAX_HITCH_MS=100
MAX_OVER_BUDGET_FRACTION=0.01

refresh_hz() {
  # Read the panel's actual refresh rate. Hardcoding 60 would silently pass a
  # ProMotion machine that was dropping every other frame.
  "$SCRIPT_DIR/fidelity-display.sh" report 2>/dev/null \
    | sed -n 's/.*"max_fps"[^0-9]*\([0-9][0-9]*\).*/\1/p' | head -1
}

case "${1:?usage: record|analyse}" in
  record)
    TAG=${2:?tag}; OUT=${3:?output .trace path}
    # The precondition is not optional, and it now covers the WINDOW as well as the
    # display. Recording on the wrong display mode, or on a window macOS silently
    # clamped to fit it, produces a number that looks like a measurement and is not one.
    "$SCRIPT_DIR/fidelity-display.sh" check "cmux DEV $TAG"
    HZ=$(refresh_hz); HZ=${HZ:-60}
    echo "H4: recording against a ${HZ} Hz panel; budget $(python3 -c "print(round(1000.0/$HZ,3))") ms/frame"
    PID=$(pgrep -f "cmux DEV $TAG.app/Contents/MacOS" | head -1 || true)
    if [ -z "$PID" ]; then
      echo "H4 ABORT: no running app for tag '$TAG'. Launch it with scripts/reload-carousel.sh --release first." >&2
      echo "          Row 112 measures the Release configuration, not the Debug one -- measuring an" >&2
      echo "          unoptimized build against a frame-rate gate produces a failure unrelated to the" >&2
      echo "          motion code, or a waiver that launders a failure into a pass." >&2
      exit 1
    fi
    echo "H4: attaching to pid $PID"
    xctrace record --template "Animation Hitches" --attach "$PID" --output "$OUT" --time-limit 20s
    echo "H4: wrote $OUT"
    echo "H4: drive the switch, the grid toggle and the five-press burst DURING the 20 s window."
    ;;
  analyse)
    OUT=${2:?trace path}
    HZ=$(refresh_hz); HZ=${HZ:-60}
    BUDGET_MS=$(python3 -c "print(1000.0/$HZ)")
    echo "H4 analysis of $OUT against a ${HZ} Hz panel (${BUDGET_MS} ms budget)"
    # xctrace exports the hitch table as XML; the thresholds are applied here rather
    # than read off a summary screen so the verdict is reproducible.
    TMPXML=$(mktemp)
    trap 'rm -f "$TMPXML"' EXIT
    xctrace export --input "$OUT" --xpath '/trace-toc/run/data/table[@schema="animation-hitch"]' \
      > "$TMPXML" 2>/dev/null || {
        echo "H4: could not export the animation-hitch table from $OUT." >&2
        echo "    List the available schemas with:  xctrace export --input '$OUT' --toc" >&2
        exit 2; }
    python3 - "$TMPXML" "$MAX_HITCH_MS" "$MAX_OVER_BUDGET_FRACTION" "$BUDGET_MS" <<'PY'
import sys, xml.etree.ElementTree as ET
path, max_hitch_ms, max_frac, budget_ms = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
root = ET.parse(path).getroot()
durations = []
for node in root.iter():
    if node.tag in ("duration", "hitch-duration") and (node.text or "").strip():
        try:
            durations.append(float(node.text) / 1e6)  # ns -> ms
        except ValueError:
            pass
if not durations:
    print("H4: the exported table contained no hitch durations.")
    print("    An empty table is NOT a pass -- it is an unproven run. Confirm the")
    print("    recording actually captured the switch, the grid toggle and the burst.")
    raise SystemExit(2)
worst = max(durations)
over = [d for d in durations if d > budget_ms]
frac = len(over) / float(len(durations))
print("frames sampled: %d   worst hitch: %.2f ms   over budget: %d (%.3f%%)"
      % (len(durations), worst, len(over), frac * 100))
fail = 0
if worst > max_hitch_ms:
    print("FAIL: worst hitch %.2f ms exceeds the %.0f ms bound" % (worst, max_hitch_ms)); fail = 1
if frac > max_frac:
    print("FAIL: %.3f%% of frames over budget exceeds %.1f%%" % (frac * 100, max_frac * 100)); fail = 1
print("ROW 112: %s" % ("PASS" if not fail else "FAIL"))
raise SystemExit(fail)
PY
    ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
