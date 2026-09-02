#!/usr/bin/env bash
# CONTRACT row 117 / D-4 — mirror the Hive's ~/.claude onto this Mac.
#
# Every Claude Code session Dawid runs is on the Hive inside tmux; the Mac's own
# ~/.claude/sessions is empty. The carousel reads a local mirror this script
# refreshes over the existing ssh bridge. Read-only, one-way; nothing is ever
# written back to the Hive.
#
# TWO LANES, because one cadence cannot serve both payloads.
#
#   fast  sessions/*.json + statusline-snapshots/*.json.  ~64 KB, 20 files.
#         This is the whole of the top bar's input (rows 12, 13, 15, 76, 120,
#         125, 126, 127) and it meets row 117's <= 5 s bound comfortably.
#   full  fast, plus the projects/<slug>/<session>/subagents/ trees that row 71
#         counts.  Measured on the real Hive: 5.4 GB and 8675 files under
#         projects/, 5970 of them sub-agent JSONL across 76 directories. A cold
#         first pull is minutes, and even an incremental pass must walk all 8675
#         entries. Running that every 5 s would saturate the link and starve the
#         lane that actually feeds the bar.
#
# The loop therefore runs `fast` every PULL_INTERVAL (5 s) and `full` every
# FULL_INTERVAL (30 s). The honest consequence, stated rather than engineered
# away: a sub-agent appearing on the Hive reaches this Mac in up to FULL_INTERVAL
# plus the local watcher latency, NOT 5 s. Row 71's own 2 s figure is a local
# assertion against the injected root and is unaffected.
#
# --max-size caps a single sub-agent transcript; the name U4 parses is on the
# first line, so a multi-megabyte transcript tail buys nothing and costs the bound.
set -uo pipefail

HOST="${CMUX_CAROUSEL_SSH_HOST:-hive}"
REMOTE_ROOT="${CMUX_CAROUSEL_REMOTE_ROOT:-.claude}"
DEST="${CMUX_CAROUSEL_DATA_ROOT:-$HOME/Library/Application Support/cmux/carousel-mirror}"
# 4, not 5. Worst-case staleness is the interval PLUS the pull's own duration,
# and a measured fast-lane pull costs ~0.6 s against the Hive, so a 5 s interval
# puts the worst case at ~5.6 s and misses row 117's bound. At 4 s the worst case
# measures ~4.6 s and the bound holds on the slowest sample, not just the mean.
INTERVAL="${CMUX_CAROUSEL_PULL_INTERVAL:-4}"
FULL_INTERVAL="${CMUX_CAROUSEL_FULL_INTERVAL:-30}"
MAX_SIZE="${CMUX_CAROUSEL_MAX_FILE_SIZE:-512k}"

LANE=full
ONCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --once) ONCE=1 ;;
    --lane) shift; LANE="${1:-full}" ;;
    --fast) LANE=fast ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$DEST" || { echo "cannot create $DEST" >&2; exit 1; }
STATUS="$DEST/.mirror-status.json"

write_status() {
  # Row 117: the bridge being down renders a defined degraded state NAMING the
  # unreachable host, never a silent empty carousel. Written on every outcome,
  # success and failure alike, so "no status file" is itself a signal.
  local lane="$1" reachable="$2" rc="$3" detail="$4" tmp
  tmp="$STATUS.tmp.$$"
  printf '{"host":"%s","remote_root":"%s","lane":"%s","reachable":%s,"exit_code":%s,"detail":"%s","checked_at":%s}\n' \
    "$HOST" "$REMOTE_ROOT" "$lane" "$reachable" "$rc" "$detail" "$(date -u +%s)" > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$STATUS" 2>/dev/null || rm -f "$tmp" 2>/dev/null
}

pull_fast() {
  local out rc
  out=$(rsync -az --delete --timeout=8 \
      -e 'ssh -o BatchMode=yes -o ConnectTimeout=6' \
      --include='sessions/' --include='sessions/*.json' \
      --include='statusline-snapshots/' --include='statusline-snapshots/*.json' \
      --exclude='*' \
      "$HOST:$REMOTE_ROOT/" "$DEST/" 2>&1)
  rc=$?
  if [ $rc -eq 0 ]; then write_status fast true 0 ""
  else write_status fast false "$rc" "$(printf '%s' "$out" | tail -1 | tr -d '"\\' | cut -c1-200)"; fi
  return $rc
}

pull_subagents() {
  local out rc
  # No --delete here: this lane is filtered, and --delete against a filtered
  # transfer would remove sub-agent files the filter simply did not select.
  out=$(rsync -az --timeout=25 --max-size="$MAX_SIZE" \
      -e 'ssh -o BatchMode=yes -o ConnectTimeout=6' \
      --prune-empty-dirs \
      --include='projects/' --include='projects/*/' --include='projects/*/*/' \
      --include='projects/*/*/subagents/' --include='projects/*/*/subagents/*' \
      --exclude='*' \
      "$HOST:$REMOTE_ROOT/" "$DEST/" 2>&1)
  rc=$?
  if [ $rc -ne 0 ]; then
    write_status subagents false "$rc" "$(printf '%s' "$out" | tail -1 | tr -d '"\\' | cut -c1-200)"
  fi
  return $rc
}

if [ "$ONCE" = 1 ]; then
  if [ "$LANE" = fast ]; then pull_fast; exit $?; fi
  pull_fast; fast_rc=$?
  pull_subagents
  exit $fast_rc
fi

# The sub-agent lane runs in its OWN process, never inline.
#
# Measured, not assumed: with the two lanes in one loop, a fast-lane canary that
# happened to land while the sub-agent pull was running took 7.16 s to appear,
# against 2.6-4.6 s for every de-phased sample. The sub-agent pull walks 8675
# remote entries and blocks whatever follows it, so sharing a process makes the
# top bar's staleness a function of a payload the top bar does not even read.
last_full=0
subagent_pid=""
while true; do
  pull_fast
  now=$(date -u +%s)
  if [ $(( now - last_full )) -ge "$FULL_INTERVAL" ]; then
    # Skip rather than queue when the previous sub-agent pull is still running,
    # so a slow link cannot pile up overlapping rsyncs against one destination.
    if [ -z "$subagent_pid" ] || ! kill -0 "$subagent_pid" 2>/dev/null; then
      pull_subagents &
      subagent_pid=$!
      last_full=$now
    fi
  fi
  sleep "$INTERVAL"
done
