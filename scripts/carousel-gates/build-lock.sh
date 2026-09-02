#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui, shared-Mac build slot).
#
# One build slot for the whole Mac. Six agents share this machine and the real
# contention is the shared SwiftPM package cache and the CPU, not derivedDataPath, so
# the slot is global rather than per-worktree. PROVISION.md documents a plain-text
# advisory file at /tmp/cmux-build.lock with a check-then-write acquire, which has a
# TOCTOU window: two agents can both read FREE and both write.
#
# This helper closes that window with mkdir(2), which is atomic on every POSIX
# filesystem, while still writing the SAME four fields at the SAME path the other
# agents read, so it stays compatible with the convention already in use. An agent
# using the documented check-then-write path still sees a held lock; an agent using
# this helper cannot lose the race.
#
#   build-lock.sh acquire <owner> <worktree> <tag> [timeout_seconds]
#   build-lock.sh release <owner>
#   build-lock.sh status
#   build-lock.sh with <owner> <worktree> <tag> -- <command...>   # acquire, run, always release
set -uo pipefail

LOCK_DIR=/tmp/cmux-build.lock.d
LOCK_FILE=/tmp/cmux-build.lock
STALE_SECONDS=${CMUX_LOCK_STALE_SECONDS:-1800}

now() { date +%s; }

write_fields() {
  cat > "$LOCK_FILE" <<EOT
owner=$1
started=$(date)
worktree=$2
tag=$3
EOT
  printf '%s\n' "$1" > "$LOCK_DIR/owner"
  now > "$LOCK_DIR/started_epoch"
}

is_stale() {
  [ -d "$LOCK_DIR" ] || return 1
  local started age
  started=$(cat "$LOCK_DIR/started_epoch" 2>/dev/null || echo 0)
  age=$(( $(now) - started ))
  [ "$age" -gt "$STALE_SECONDS" ] || return 1
  # Age alone is not staleness. PROVISION.md is explicit: confirm no build is
  # actually running before treating a lock as abandoned, because a long build is
  # the normal case here -- a clean cmux build took 726 s on this machine.
  if pgrep -fl 'xcodebuild -project cmux|reload.sh|reloadp.sh' >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

acquire() {
  local owner=$1 worktree=$2 tag=$3 timeout=${4:-3600}
  local deadline=$(( $(now) + timeout ))
  while true; do
    # Both gates must be clear. The directory is the atomic one; the plain file is
    # the convention PROVISION.md documents and other agents on this Mac still write,
    # so ignoring it would let this script build straight through their lock.
    if [ ! -e "$LOCK_FILE" ] && mkdir "$LOCK_DIR" 2>/dev/null; then
      write_fields "$owner" "$worktree" "$tag"
      echo "lock acquired by $owner"
      return 0
    fi
    if is_stale; then
      echo "lock at $LOCK_DIR is older than ${STALE_SECONDS}s and no xcodebuild/reload.sh is running:" >&2
      cat "$LOCK_FILE" 2>/dev/null >&2
      echo "NOT removing it automatically -- PROVISION.md requires posting to the team first." >&2
      echo "To override deliberately: rm -rf $LOCK_DIR $LOCK_FILE" >&2
      return 3
    fi
    if [ "$(now)" -ge "$deadline" ]; then
      echo "timed out waiting for the build lock; held by:" >&2
      cat "$LOCK_FILE" 2>/dev/null >&2
      return 2
    fi
    sleep 10
  done
}

release() {
  local owner=${1:-}
  local held
  held=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo "")
  if [ ! -d "$LOCK_DIR" ]; then echo "lock already free"; return 0; fi
  # Another agent on this Mac holds the same directory with only a `pid` file and no
  # `owner`. An absent owner therefore means "someone else's lock", never "unowned" --
  # treating it as unowned would delete a running agent's build slot.
  if [ -z "$held" ]; then
    echo "refusing to release: $LOCK_DIR has no owner file, so it belongs to another agent's" >&2
    echo "lock convention. Contents:" >&2
    ls -la "$LOCK_DIR" >&2; cat "$LOCK_FILE" 2>/dev/null >&2
    return 1
  fi
  if [ -n "$owner" ] && [ "$owner" != "$held" ]; then
    echo "refusing to release: lock is held by '$held', not '$owner'" >&2
    return 1
  fi
  rm -f "$LOCK_FILE"
  rm -rf "$LOCK_DIR"
  echo "lock released"
}

case "${1:-status}" in
  acquire) shift; acquire "$@" ;;
  release) shift; release "${1:-}" ;;
  status)
    if [ -d "$LOCK_DIR" ]; then echo "HELD"; cat "$LOCK_FILE" 2>/dev/null; else echo "FREE"; fi
    ;;
  with)
    shift
    owner=$1; worktree=$2; tag=$3; shift 3
    [ "${1:-}" = "--" ] && shift
    acquire "$owner" "$worktree" "$tag" || exit $?
    # Release on every exit path, including a signal, so a killed session does not
    # strand the slot -- the failure mode PROVISION.md names.
    trap 'release "$owner" >/dev/null 2>&1' EXIT INT TERM
    "$@"
    exit $?
    ;;
  *) sed -n '2,18p' "$0"; exit 2 ;;
esac
