#!/usr/bin/env bash
# Modified 2026-09-03 for the cmux carousel build (cmux-carousel-ui; shared Mac build slot).
#
# THE build-slot lock for every agent on this Mac. Team-lead ruling, 2026-09-03: the one
# canonical lock is /tmp/cmux-build.lock.d, a mkdir-lock holding `pid` and `unit`; no
# agent touches a lock path by hand again, and every build goes through this script.
#
#   cmux-build-lock.sh acquire <unit> [timeout_s]     take the slot, or wait for it
#   cmux-build-lock.sh release <unit>                 give it back
#   cmux-build-lock.sh run <unit> -- <command...>     acquire, run, ALWAYS release
#   cmux-build-lock.sh status                         who holds it, and is it real
#   cmux-build-lock.sh reap                           remove a provably stranded lock
#
# `run` is the one to use. It releases on every exit path including a signal, which is
# the failure PROVISION.md names: a killed session strands the slot for everyone.
#
# TWO CONDITIONS, BOTH REQUIRED, before a build starts: no `xcodebuild` is running
# anywhere on the machine, AND this script holds the lock directory. The lock is a
# courtesy between agents; a running xcodebuild is a fact, and three of them landed on
# this Mac at once before the ruling.
#
# Liveness is checked with `kill -0` on the recorded pid, never by grepping a command
# line. A pattern like `pgrep -f 'xcodebuild -project'` matches the very shell running
# it whenever that string is in its own argv, so a waiter can see itself as the build it
# is waiting for and block forever. That happened here: orphaned waiter loops were found
# and killed on this Mac. Build detection uses `pgrep -x xcodebuild`, which matches the
# executable name and cannot match a shell.
#
# Legacy shapes are treated as HELD until reaped: the deprecated plain file or directory
# at /tmp/cmux-build.lock, and the old /tmp/cmux-build.lock.meta. This script never
# CREATES them. Ignoring them would build straight through an agent that has not yet
# switched over.
set -uo pipefail

LOCK=/tmp/cmux-build.lock.d
LEGACY_PATHS=(/tmp/cmux-build.lock /tmp/cmux-build.lock.meta)
LOG=/tmp/cmux-build-lock.log
STALE_SECONDS=${CMUX_LOCK_STALE_SECONDS:-1800}   # 30 minutes, the team norm

now() { date +%s; }

# mtime in epoch seconds; BSD stat on macOS, GNU stat elsewhere.
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

# --- disk floor -------------------------------------------------------------------
# The data volume hit 99 % with a dozen cmux-* DerivedData trees. A build that starts
# with no room does not fail cleanly: it half-writes DerivedData, corrupts the SwiftPM
# artifact cache, and the next agent inherits the wreckage. Refusing the slot is the
# cheaper failure.
MIN_FREE_GIB=${CMUX_MIN_FREE_GIB:-15}

free_gib() { df -Pk / | awk 'NR==2 {printf "%d", $4/1048576}'; }

derived_data_report() {
  local dd="$HOME/Library/Developer/Xcode/DerivedData"
  [ -d "$dd" ] || return 0
  echo "  DerivedData trees, largest first:" >&2
  du -sk "$dd"/* 2>/dev/null | sort -rn | head -12 \
    | awk '{ printf "    %6.1f GiB  %s\n", $1/1048576, $2 }' >&2
}

disk_ok() {
  local free; free=$(free_gib)
  [ -n "$free" ] || return 0            # cannot measure: do not block on a broken df
  [ "$free" -ge "$MIN_FREE_GIB" ] && return 0
  echo "DISK FLOOR: ${free} GiB free on the data volume, ${MIN_FREE_GIB} GiB required." >&2
  echo "  Waiting will NOT help -- nothing here frees disk. Someone has to delete a tree." >&2
  derived_data_report
  log "REFUSE-DISK free=${free}GiB min=${MIN_FREE_GIB}GiB"
  return 1
}

log() {
  printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# Processes actually building. `-x` matches the executable name, so this can never
# match the shell that runs it, unlike a `-f` pattern over the command line.
builds_running() { pgrep -x xcodebuild >/dev/null 2>&1; }
build_pids()     { pgrep -x xcodebuild 2>/dev/null | tr '\n' ' '; }

holder_pid()  { cat "$LOCK/pid"  2>/dev/null; }
holder_unit() { cat "$LOCK/unit" 2>/dev/null; }
# A MISSING started_epoch is UNKNOWN age, never zero. Defaulting it to 0 would make
# every lock written by another helper -- which records only a pid -- compute as
# epoch-old, and any age-based branch would then fire on a perfectly live holder.
# -1 means unknown and no comparison against the staleness norm can be true for it.
holder_age()  {
  local s; s=$(cat "$LOCK/started_epoch" 2>/dev/null || echo "")
  case "$s" in
    ''|*[!0-9]*) echo -1 ;;
    *) [ "$s" -gt 0 ] && echo $(( $(now) - s )) || echo -1 ;;
  esac
}

# Alive means the recorded pid answers kill -0. A lock with no pid file records no
# holder, so it cannot be alive -- that is the old convention's shape, not a live agent.
holder_alive() {
  local p; p=$(holder_pid)
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

legacy_present() {
  local p
  for p in "${LEGACY_PATHS[@]}"; do [ -e "$p" ] && return 0; done
  return 1
}

# A lock is stranded only when BOTH hold: its holder process is gone, and no build is
# running. Age alone never strands a lock -- a clean cmux build takes about twelve
# minutes here, so a young lock is normal and an old one can still be legitimate.
reap() {
  local reaped=0 p
  if [ -d "$LOCK" ] && ! holder_alive && ! builds_running; then
    log "REAP $LOCK holder_pid=$(holder_pid) unit=$(holder_unit) age=$(holder_age)s reason=holder-dead-and-no-xcodebuild"
    rm -rf "$LOCK"; reaped=1
  fi
  # A legacy path can itself be somebody's live lock, so "no build is running" is not
  # enough to delete it: an agent that has just acquired and not yet spawned xcodebuild
  # looks identical to an abandoned file. Require a recorded holder that is DEAD, or no
  # recorded holder at all AND an age past the staleness norm. Never age alone, and
  # never liveness alone.
  for p in "${LEGACY_PATHS[@]}"; do
    [ -e "$p" ] || continue
    builds_running && continue
    local lpid lage
    lpid=$( { [ -d "$p" ] && cat "$p/pid"; } 2>/dev/null || true)
    if [ -n "$lpid" ] && kill -0 "$lpid" 2>/dev/null; then
      continue   # a live holder recorded in a deprecated path is still a live holder
    fi
    lage=$(( $(now) - $(file_mtime "$p") ))
    if [ -z "$lpid" ] && [ "$lage" -lt "$STALE_SECONDS" ]; then
      continue   # no holder recorded and recently touched: assume somebody just took it
    fi
    log "REAP $p (deprecated path) holder_pid=${lpid:-none} age=${lage}s reason=no-live-holder-and-no-xcodebuild"
    rm -rf "$p"; reaped=1
  done
  [ "$reaped" -eq 1 ] && echo "reaped a stranded lock; see $LOG"
  return 0
}

acquire() {
  local unit=${1:?usage: acquire <unit> [timeout_s]} timeout=${2:-7200}
  local deadline=$(( $(now) + timeout ))
  local warned=0
  disk_ok || return 4
  while true; do
    reap >/dev/null
    if ! builds_running && ! legacy_present && mkdir "$LOCK" 2>/dev/null; then
      printf '%s\n' "$$"      > "$LOCK/pid"
      printf '%s\n' "$unit"   > "$LOCK/unit"
      now                     > "$LOCK/started_epoch"
      log "ACQUIRE unit=$unit pid=$$"
      echo "build slot acquired by $unit (pid $$)"
      return 0
    fi
    # An ALIVE holder past the staleness norm is reported, never auto-reaped: the team
    # requires posting before removing another agent's live lock.
    local age; age=$(holder_age)
    if [ "$warned" -eq 0 ] && holder_alive && [ "$age" -gt "$STALE_SECONDS" ] 2>/dev/null; then
      echo "NOTE: $(holder_unit) has held the slot ${age}s (norm ${STALE_SECONDS}s) and its pid $(holder_pid) is ALIVE." >&2
      echo "      Post to the team before removing it. Waiting." >&2
      log "STALE-ALIVE unit=$(holder_unit) pid=$(holder_pid) age=${age}s waiter=$unit"
      warned=1
    fi
    if [ "$(now)" -ge "$deadline" ]; then
      echo "timed out after ${timeout}s waiting for the build slot." >&2
      status >&2
      return 2
    fi
    sleep 10
  done
}

release() {
  local unit=${1:-}
  if [ ! -d "$LOCK" ]; then echo "build slot already free"; return 0; fi
  local held; held=$(holder_unit)
  if [ -z "$held" ]; then
    echo "refusing to release: $LOCK records no unit, so it is not this script's lock." >&2
    ls -la "$LOCK" >&2
    return 1
  fi
  if [ -n "$unit" ] && [ "$unit" != "$held" ]; then
    echo "refusing to release: the slot is held by '$held', not '$unit'." >&2
    return 1
  fi
  log "RELEASE unit=$held pid=$(holder_pid)"
  rm -rf "$LOCK"
  echo "build slot released by $held"
}

status() {
  if builds_running; then
    echo "BUILDING: xcodebuild pids $(build_pids)"
  fi
  if [ -d "$LOCK" ]; then
    echo "HELD by $(holder_unit) (pid $(holder_pid), $(holder_age)s)"
    holder_alive && echo "  holder is ALIVE" || echo "  holder is DEAD -> run 'reap'"
  fi
  legacy_present && echo "LEGACY lock path present (deprecated): $(ls -d "${LEGACY_PATHS[@]}" 2>/dev/null | tr '\n' ' ')"
  if [ ! -d "$LOCK" ] && ! legacy_present && ! builds_running; then echo "FREE"; fi
  return 0
}

case "${1:-status}" in
  acquire) shift; acquire "$@" ;;
  release) shift; release "${1:-}" ;;
  status)  status ;;
  reap)    reap; status ;;
  run)
    shift
    unit=${1:?usage: run <unit> -- <command...>}; shift
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || { echo "usage: run <unit> -- <command...>" >&2; exit 2; }
    acquire "$unit" "${CMUX_LOCK_TIMEOUT:-7200}" || exit $?
    trap 'release "'"$unit"'" >/dev/null 2>&1' EXIT INT TERM HUP
    "$@"
    exit $?
    ;;
  ""|-h|--help) sed -n '2,30p' "$0"; exit 2 ;;
  *)
    # /tmp/cmux-build-lock.sh was a separate 13-line mutex taking a BARE command
    # (`cmux-build-lock.sh xcodebuild ...`). That path is now a symlink here, so its
    # callers would otherwise land in the usage branch and never build. Anything that
    # is not a known action is treated as a bare command under an inferred unit name,
    # which keeps every existing call site working while it converges on `run`.
    echo "note: bare-command form; treating as: run ${CMUX_UNIT:-legacy-caller} -- $*" >&2
    acquire "${CMUX_UNIT:-legacy-caller}" "${CMUX_LOCK_TIMEOUT:-7200}" || exit $?
    trap 'release "${CMUX_UNIT:-legacy-caller}" >/dev/null 2>&1' EXIT INT TERM HUP
    "$@"
    exit $?
    ;;
esac
