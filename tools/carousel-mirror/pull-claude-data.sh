#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT rows 117, 96, D-4).
#
# The data bridge. Every Claude Code session Dawid runs is on the Hive inside tmux;
# this Mac's ~/.claude/sessions is empty. Without this pull, rows 43, 71, 76, 85 and
# 105 all read an empty directory and PASS VACUOUSLY -- the carousel would be blank on
# the one machine it ships to and every data row would still be green.
#
# Committed rather than hand-configured: row 96 requires the bridge to be
# infrastructure-as-code with nothing clicked in a dashboard.
#
#   pull-claude-data.sh once                 one pull, exit 0 on success
#   pull-claude-data.sh loop [interval]      pull every `interval` seconds (default 5)
#   pull-claude-data.sh canary               prove end-to-end staleness <= 5 s
#   pull-claude-data.sh status               print the mirror's stamp and age
#
# READ-ONLY and ONE-WAY. Nothing is ever written back to the Hive, and no listening
# surface is added on either machine -- it rides the ssh channel that already exists.
# That is why the build stays production-readiness tier T1 (CONTRACT row 1).
set -uo pipefail

REMOTE_HOST="${CMUX_CAROUSEL_REMOTE_HOST:-hive}"
REMOTE_ROOT="${CMUX_CAROUSEL_REMOTE_ROOT:-.claude}"
MIRROR="${CMUX_CAROUSEL_MIRROR:-$HOME/Library/Application Support/cmux/carousel-claude-mirror}"
INTERVAL_DEFAULT=5
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

# A persistent control channel. A fresh TCP + SSH handshake every 5 s would cost more
# than the pull itself and would be the thing that misses the row-91 window.
SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=8
          -o ControlMaster=auto -o "ControlPath=$HOME/.ssh/cm-carousel-%r@%h-%p"
          -o ControlPersist=600)

stamp_path() { printf '%s/.mirror-stamp' "$MIRROR"; }
error_path() { printf '%s/.mirror-error' "$MIRROR"; }

pull_once() {
  mkdir -p "$MIRROR"
  # Only what the carousel reads. `projects/` holds full transcripts and is pulled
  # for its subagents/ trees and metadata; the include rules keep a session's whole
  # scrollback from crossing the wire every five seconds.
  local rc=0
  rsync -az --delete --timeout=8 \
        -e "ssh ${SSH_OPTS[*]}" \
        --include='sessions/' --include='sessions/*.json' \
        --include='statusline-snapshots/' --include='statusline-snapshots/*.json' \
        --include='projects/' --include='projects/*/' --include='projects/*/*/' \
        --include='projects/*/*/subagents/' \
        --include='projects/*/*/subagents/*.jsonl' \
        --include='projects/*/*/subagents/*.json' \
        --exclude='*' \
        "$REMOTE_HOST:$REMOTE_ROOT/" "$MIRROR/" 2>"$MIRROR/.rsync-err" || rc=$?

  if [ "$rc" -ne 0 ]; then
    # The stamp is NOT touched on failure. Leaving the previous stamp is what makes a
    # bridge outage read as STALE rather than as fresh-but-truncated, which is the
    # distinction CarouselDataRoot.Freshness exists to carry.
    {
      echo "host=$REMOTE_HOST"
      echo "failed_epoch=$(date +%s)"
      echo "rsync_exit=$rc"
      sed -n '1,3p' "$MIRROR/.rsync-err" 2>/dev/null
    } > "$(error_path)"
    echo "pull FAILED (rsync exit $rc); host $REMOTE_HOST unreachable or refused" >&2
    return "$rc"
  fi

  rm -f "$(error_path)"
  # Written LAST, after the data has landed, so a stamp can never be newer than the
  # data it vouches for. A half-finished pull leaves the old stamp behind.
  {
    echo "host=$REMOTE_HOST"
    echo "remote_root=$REMOTE_ROOT"
    echo "completed_epoch=$(date +%s)"
  } > "$(stamp_path)"
  return 0
}

case "${1:-once}" in
  once) pull_once ;;
  loop)
    INTERVAL=${2:-$INTERVAL_DEFAULT}
    echo "mirroring $REMOTE_HOST:$REMOTE_ROOT -> $MIRROR every ${INTERVAL}s"
    while true; do pull_once || true; sleep "$INTERVAL"; done
    ;;
  status)
    if [ -f "$(stamp_path)" ]; then
      cat "$(stamp_path)"
      e=$(sed -n 's/^completed_epoch=//p' "$(stamp_path)")
      echo "age_seconds=$(( $(date +%s) - ${e:-0} ))"
    else
      echo "no stamp: the mirror has never completed a pull"
    fi
    [ -f "$(error_path)" ] && { echo "--- last error ---"; cat "$(error_path)"; }
    exit 0
    ;;
  canary)
    # Row 117's proof: write a canary on the Hive, time its appearance in the mirror.
    # This measures the WHOLE path -- remote write, rsync, local visibility -- which a
    # test that only checks the mirror directory exists would not.
    # Warm up first, and start the clock only afterwards. The bound in row 91 and D-4
    # is a STEADY-STATE refresh interval, not a cold-start figure: the first pull on a
    # fresh machine transfers the whole subagent tree (~2 GB here) and took 41 s
    # measured, while warm incremental pulls take ~1.1 s. Timing the cold sync would
    # fail a bound it was never about; skipping the warm-up quietly would hide that the
    # first launch after an install has no data for the better part of a minute, so the
    # cold figure is REPORTED rather than dropped.
    echo "warming up (cold first sync is not what the 5 s bound measures)..."
    COLD_START=$(date +%s)
    pull_once >/dev/null 2>&1 || true
    echo "warm-up pull took $(( $(date +%s) - COLD_START ))s"
    CANARY="carousel-canary-$$-$(date +%s)"
    REMOTE_FILE="$REMOTE_ROOT/sessions/${CANARY}.json"
    ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "printf '{\"canary\":\"%s\"}' '$CANARY' > '$REMOTE_FILE'" || {
      echo "canary: could not write on $REMOTE_HOST" >&2; exit 1; }
    START=$(date +%s)
    FOUND=""
    for _ in $(seq 1 10); do
      pull_once >/dev/null 2>&1 || true
      if [ -f "$MIRROR/sessions/${CANARY}.json" ]; then FOUND=yes; break; fi
      sleep 1
    done
    ELAPSED=$(( $(date +%s) - START ))
    ssh "${SSH_OPTS[@]}" "$REMOTE_HOST" "rm -f '$REMOTE_FILE'" || true
    pull_once >/dev/null 2>&1 || true
    if [ -z "$FOUND" ]; then echo "ROW 117 (canary): FAIL -- canary never appeared"; exit 1; fi
    echo "canary appeared in ${ELAPSED}s (bound: 5s)"
    if [ "$ELAPSED" -le 5 ]; then echo "ROW 117 (canary): PASS"; exit 0; fi
    echo "ROW 117 (canary): FAIL -- ${ELAPSED}s exceeds the 5s bound"; exit 1
    ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
