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
#   cmux-build-lock.sh queue                          the waiting order, front first
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

# --- FIFO ticket queue ------------------------------------------------------------
# Without this, every waiter polls the same mkdir and whoever happens to win the race
# builds. With eight jobs waiting that is not a queue, it is a lottery: U1, first in the
# ruled order, waited 33 minutes while later arrivals went ahead of it.
#
# A waiter now takes a numbered ticket and only ATTEMPTS the mkdir when its ticket is
# the lowest live one. The mkdir stays as the actual mutex -- the queue decides whose
# turn it is, the mkdir still guarantees only one winner if two agree they are next.
#
# Ordering is (priority, sequence). Priority comes from an optional order file, one unit
# per line; a listed unit sorts ahead of every unlisted one, and unlisted units keep
# plain arrival order among themselves.
QUEUE=/tmp/cmux-build-queue.d
SEQ_MUTEX=/tmp/cmux-build-seq.mutex.d
SEQ_FILE=/tmp/cmux-build-queue.d/.seq
ORDER_FILE=${CMUX_BUILD_ORDER_FILE:-/tmp/cmux-build-order}
TICKET=""

# The counter is incremented under its OWN mkdir mutex, separate from the build slot.
# Read-modify-write on a shared file is not atomic, and two agents taking a ticket in
# the same instant would otherwise get the same number and both believe they are next.
next_seq() {
  local n=0 waited=0
  mkdir -p "$QUEUE" 2>/dev/null
  while ! mkdir "$SEQ_MUTEX" 2>/dev/null; do
    sleep 0.2
    waited=$((waited + 1))
    # The counter mutex is held for microseconds. Seconds of contention means a crashed
    # holder, not a busy one, so break the deadlock rather than wait out the build.
    if [ "$waited" -gt 50 ]; then
      log "SEQ-MUTEX-BREAK held over 10s, assuming a crashed holder"
      rm -rf "$SEQ_MUTEX"
    fi
  done
  n=$(cat "$SEQ_FILE" 2>/dev/null || echo 0)
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  n=$((n + 1))
  printf '%s\n' "$n" > "$SEQ_FILE"
  rmdir "$SEQ_MUTEX" 2>/dev/null
  printf '%s\n' "$n"
}

take_ticket() {
  local unit=$1 n
  n=$(next_seq)
  TICKET="$QUEUE/$(printf '%06d' "$n")-$unit"
  printf '%s\n' "$$" > "$TICKET"
  log "TICKET unit=$unit seq=$n pid=$$"
  echo "queued as ticket $(basename "$TICKET")" >&2
}

drop_ticket() {
  [ -n "$TICKET" ] && rm -f "$TICKET" 2>/dev/null
  TICKET=""
}

# A ticket whose holder is gone would block the whole queue forever, so liveness is
# checked by kill -0 on the pid inside, the same test the lock itself uses.
reap_dead_tickets() {
  local t p
  for t in "$QUEUE"/*; do
    [ -f "$t" ] || continue
    case "$(basename "$t")" in .seq) continue ;; esac
    p=$(cat "$t" 2>/dev/null || echo "")
    if [ -z "$p" ] || ! kill -0 "$p" 2>/dev/null; then
      log "TICKET-REAP $(basename "$t") pid=${p:-none} reason=holder-dead"
      rm -f "$t" 2>/dev/null
    fi
  done
}

# Position in the order file, or a large number when unlisted.
priority_of() {
  local unit=$1 i=1 line
  [ -f "$ORDER_FILE" ] || { echo 9999; return; }
  while IFS= read -r line; do
    line=$(printf '%s' "$line" | tr -d '[:space:]')
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    if [ "$line" = "$unit" ]; then echo "$i"; return; fi
    i=$((i + 1))
  done < "$ORDER_FILE"
  echo 9999
}

# The sort key for a ticket file: priority first, arrival second.
ticket_key() {
  local base=$1 seq unit
  seq=${base%%-*}
  unit=${base#*-}
  printf '%04d:%s' "$(priority_of "$unit")" "$seq"
}

my_turn() {
  [ -n "$TICKET" ] || return 0
  reap_dead_tickets
  local best="" t k mine
  mine=$(ticket_key "$(basename "$TICKET")")
  for t in "$QUEUE"/*; do
    [ -f "$t" ] || continue
    case "$(basename "$t")" in .seq) continue ;; esac
    k=$(ticket_key "$(basename "$t")")
    if [ -z "$best" ] || [ "$k" \< "$best" ]; then best=$k; fi
  done
  [ "$mine" = "$best" ]
}

queue_report() {
  local t
  [ -d "$QUEUE" ] || return 0
  echo "  queue, in service order:" >&2
  for t in "$QUEUE"/*; do
    [ -f "$t" ] || continue
    case "$(basename "$t")" in .seq) continue ;; esac
    printf '%s\t%s\tpid %s\n' "$(ticket_key "$(basename "$t")")" "$(basename "$t")" "$(cat "$t" 2>/dev/null)"
  done | sort | awk '{ printf "    %s  (pid %s)\n", $2, $4 }' >&2
}

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
  take_ticket "$unit"
  # The ticket is dropped on every exit path, or a crashed waiter blocks the queue
  # until its ticket is reaped.
  trap 'drop_ticket' EXIT INT TERM HUP
  while true; do
    reap >/dev/null
    # Only the front of the queue even attempts the mutex. The mkdir still decides,
    # so a disagreement about whose turn it is cannot produce two builders.
    if my_turn && ! builds_running && ! legacy_present && mkdir "$LOCK" 2>/dev/null; then
      drop_ticket
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
      queue_report
      drop_ticket
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
  status)  status; queue_report ;;
  queue)   reap_dead_tickets; queue_report ;;
  reap)    reap; status ;;
  run)
    shift
    unit=${1:?usage: run <unit> -- <command...>}; shift
    [ "${1:-}" = "--" ] && shift
    [ $# -gt 0 ] || { echo "usage: run <unit> -- <command...>" >&2; exit 2; }
    # --- untagged-build guard --------------------------------------------------
    # An xcodebuild with no -derivedDataPath writes to Xcode's DEFAULT location, a tree
    # named by a hash of the project path. Those trees are invisible to every per-unit
    # cleanup, they reappear after deletion because the hash is deterministic, and they
    # are what filled the disk. reload.sh --tag always sets one, so only a bare or
    # untagged call trips this.
    #
    # Two layers, because one is not enough. The argv check catches a direct call. It
    # CANNOT see an xcodebuild nested inside `bash -c` or inside a script, which is the
    # common shape here -- so a PATH shim catches those, wherever they are nested.
    for a in "$@"; do
      case "$a" in
        *xcodebuild*)
          case " $* " in
            *" -derivedDataPath "*|*"--derived-data"*|*-showBuildSettings*|*-list*|*-version*) ;;
            *)
              echo "REFUSED: xcodebuild without -derivedDataPath." >&2
              echo "  It would write to Xcode's default DerivedData, a tree named by a hash of" >&2
              echo "  the project path. Those are invisible to per-unit cleanup and reappear" >&2
              echo "  after deletion, and they are what filled this disk." >&2
              echo "  Use ./scripts/reload.sh --tag <slug>, which always sets one." >&2
              log "REFUSE-UNTAGGED unit=$unit cmd=$*"
              exit 5 ;;
          esac ;;
      esac
    done

    # Cheap, non-blocking submodule warning. A symlinked ghostty makes every git command
    # in that worktree fail, so a build there produces commits nobody can inspect. Warn
    # rather than refuse: the build itself still works, and blocking would strand a unit
    # mid-run over something it can fix in two commands.
    for sp in ghostty vendor/bonsplit; do
      if [ -L "$sp" ]; then
        echo "WARNING: $sp is a SYMLINK in this worktree." >&2
        echo "  Every git command here fails with \"expected submodule path '$sp' not to be" >&2
        echo "  a symbolic link\", so status, diff and commit are all broken. Fix with:" >&2
        echo "    rm -rf ghostty && mkdir ghostty" >&2
        echo "    cp -R $HOME/code/cmux/vendor/bonsplit/ vendor/bonsplit/ && rm -rf vendor/bonsplit/.git" >&2
        log "WARN-SUBMODULE-SYMLINK unit=$unit path=$sp cwd=$PWD"
      fi
    done

    SHIM=$(mktemp -d)
    cat > "$SHIM/xcodebuild" <<'SHIMEOF'
#!/bin/bash
# Installed by cmux-build-lock.sh for the duration of one `run`. Refuses a build or
# test that names no -derivedDataPath, at any nesting depth, since the argv check in
# the lock script cannot see inside `bash -c` or a called script.
for arg in "$@"; do
  case "$arg" in
    -derivedDataPath) exec /usr/bin/xcodebuild "$@" ;;
    -showBuildSettings|-list|-version|-showsdks|-checkFirstLaunchStatus) exec /usr/bin/xcodebuild "$@" ;;
  esac
done
echo "REFUSED by cmux-build-lock: xcodebuild without -derivedDataPath" >&2
echo "  args: $*" >&2
echo "  Untagged builds land in Xcode's default DerivedData, a hash-named tree that is" >&2
echo "  invisible to per-unit cleanup and reappears after deletion. Use" >&2
echo "  ./scripts/reload.sh --tag <slug>, or pass -derivedDataPath explicitly." >&2
exit 5
SHIMEOF
    chmod +x "$SHIM/xcodebuild"
    export PATH="$SHIM:$PATH"

    acquire "$unit" "${CMUX_LOCK_TIMEOUT:-7200}" || { rm -rf "$SHIM"; exit $?; }
    trap 'release "'"$unit"'" >/dev/null 2>&1; rm -rf "'"$SHIM"'" 2>/dev/null' EXIT INT TERM HUP
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
