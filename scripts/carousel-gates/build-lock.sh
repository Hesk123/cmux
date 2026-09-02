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

log() {
  printf '%s\t%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG" 2>/dev/null || true
}

# Processes actually building. `-x` matches the executable name, so this can never
# match the shell that runs it, unlike a `-f` pattern over the command line.
builds_running() { pgrep -x xcodebuild >/dev/null 2>&1; }
build_pids()     { pgrep -x xcodebuild 2>/dev/null | tr '\n' ' '; }

holder_pid()  { cat "$LOCK/pid"  2>/dev/null; }
holder_unit() { cat "$LOCK/unit" 2>/dev/null; }
holder_age()  {
  local s; s=$(cat "$LOCK/started_epoch" 2>/dev/null || echo 0)
  [ "$s" -gt 0 ] 2>/dev/null && echo $(( $(now) - s )) || echo -1
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
  for p in "${LEGACY_PATHS[@]}"; do
    if [ -e "$p" ] && ! builds_running; then
      log "REAP $p (deprecated path) reason=legacy-shape-and-no-xcodebuild"
      rm -rf "$p"; reaped=1
    fi
  done
  [ "$reaped" -eq 1 ] && echo "reaped a stranded lock; see $LOG"
  return 0
}

acquire() {
  local unit=${1:?usage: acquire <unit> [timeout_s]} timeout=${2:-7200}
  local deadline=$(( $(now) + timeout ))
  local warned=0
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
  *) sed -n '2,30p' "$0"; exit 2 ;;
esac
