#!/usr/bin/env bash
# cmux-carousel-ui CONTRACT row 76 verification.
# Modified 2026-09-02 for the cmux carousel build (row 76 statusline tee verification).
#
# Proves that the statusline snapshot tee is byte-transparent:
#   1. stdout is byte-identical to the unmodified script for 10 crafted inputs
#   2. the snapshot file appears and parses as JSON
#   3. the script still exits 0 and still prints its line when the snapshot
#      directory is missing, or exists and is unwritable
#
# Usage: test-statusline-tee.sh <original.sh> <modified.sh>
set -uo pipefail

ORIG="${1:?usage: test-statusline-tee.sh <original.sh> <modified.sh>}"
MOD="${2:?usage: test-statusline-tee.sh <original.sh> <modified.sh>}"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

fail=0
note() { printf '%s\n' "$*"; }

# ---- 10 crafted fixture inputs ------------------------------------------------
mk() { printf '%s' "$1" > "$WORK/in_$2.json"; }
mk '{"session_id":"fx-01","model":{"display_name":"Claude Fable 5.1"},"context_window":{"used_percentage":63.4,"context_window_size":200000},"workspace":{"current_dir":"/tmp"}}' 01
mk '{"session_id":"fx-02","model":{"display_name":"Claude Opus 5"},"context_window":{"used_percentage":0},"cwd":"/"}' 02
mk '{"session_id":"fx-03","model":{"display_name":"Claude Sonnet 5"},"context_window":{"used_percentage":100},"workspace":{"current_dir":"/usr"}}' 03
mk '{"session_id":"fx-04","model":{"display_name":"Claude Fable 5.1"},"context_window":{"used_percentage":91.7},"session_name":"carousel","workspace":{"current_dir":"/tmp"}}' 04
mk '{"session_id":"fx-05","model":{"display_name":"Claude Haiku 4.5"},"vim":{"mode":"NORMAL"},"workspace":{"current_dir":"/tmp"}}' 05
mk '{"session_id":"fx-06","context_window":{"used_percentage":49.9},"workspace":{"current_dir":"/tmp"}}' 06
mk '{"session_id":"fx-07","model":{"display_name":"Claude Fable 5.1"}}' 07
mk '{"session_id":"fx-08","model":{"display_name":"Claude Fable 5.1"},"context_window":{"used_percentage":75},"session_name":"a b c","workspace":{"current_dir":"/tmp"}}' 08
mk '{"session_id":"fx-09","model":{"display_name":"Claude Fable 5.1"},"context_window":{"used_percentage":12.3},"rate_limits":{"five_hour":{"used_percentage":62,"resets_at":"2026-09-02T23:00:00Z"},"seven_day":{"used_percentage":41,"resets_at":"2026-09-08T00:00:00Z"}},"workspace":{"current_dir":"/tmp"}}' 09
mk '{}' 10

# ---- 1. byte-identical stdout -------------------------------------------------
export CMUX_CAROUSEL_DATA_ROOT="$WORK/root"
for i in 01 02 03 04 05 06 07 08 09 10; do
  a_out="$WORK/a_$i.out"; b_out="$WORK/b_$i.out"
  bash "$ORIG" < "$WORK/in_$i.json" > "$a_out" 2>"$WORK/a_$i.err"; a_rc=$?
  bash "$MOD"  < "$WORK/in_$i.json" > "$b_out" 2>"$WORK/b_$i.err"; b_rc=$?
  if ! cmp -s "$a_out" "$b_out"; then
    note "FAIL stdout differs on fixture $i"; diff <(xxd "$a_out") <(xxd "$b_out") | head -5; fail=1
  fi
  if [ "$a_rc" != "$b_rc" ]; then note "FAIL exit status differs on fixture $i ($a_rc vs $b_rc)"; fail=1; fi
  if [ "$b_rc" != 0 ]; then note "FAIL modified script exit $b_rc on fixture $i"; fail=1; fi
done
[ $fail -eq 0 ] && note "PASS 1/4  stdout byte-identical and exit 0 across 10 fixtures"

# ---- 2. snapshot appears and parses ------------------------------------------
snap="$WORK/root/statusline-snapshots/fx-09.json"
if [ ! -f "$snap" ]; then
  note "FAIL snapshot not written to $snap"; fail=1
elif ! jq -e '.rate_limits.five_hour.used_percentage == 62' "$snap" >/dev/null 2>&1; then
  note "FAIL snapshot did not parse or lost fields"; fail=1
else
  n=$(ls "$WORK/root/statusline-snapshots"/*.json 2>/dev/null | wc -l | tr -d ' ')
  note "PASS 2/4  snapshot written and parses ($n files; fx-09 rate_limits intact)"
fi
# a payload with no session id must not create a file
if [ -f "$WORK/root/statusline-snapshots/null.json" ]; then
  note "FAIL wrote a snapshot for a payload with no session id"; fail=1
fi

# ---- 3. missing snapshot directory -------------------------------------------
export CMUX_CAROUSEL_DATA_ROOT="$WORK/definitely/not/created/yet"
out=$(bash "$MOD" < "$WORK/in_01.json"); rc=$?
exp=$(bash "$ORIG" < "$WORK/in_01.json")
if [ "$rc" != 0 ] || [ "$out" != "$exp" ]; then
  note "FAIL missing-dir case: rc=$rc out='$out'"; fail=1
else
  note "PASS 3/4  missing snapshot directory: still exits 0, stdout unchanged"
fi

# ---- 4. unwritable snapshot directory ----------------------------------------
ro="$WORK/readonly"; mkdir -p "$ro"; chmod 500 "$ro"
export CMUX_CAROUSEL_DATA_ROOT="$ro"
out=$(bash "$MOD" < "$WORK/in_01.json"); rc=$?
if [ "$rc" != 0 ] || [ "$out" != "$exp" ]; then
  note "FAIL unwritable-dir case: rc=$rc out='$out'"; fail=1
else
  note "PASS 4/4  unwritable snapshot directory: still exits 0, stdout unchanged"
fi
chmod 700 "$ro"

if [ $fail -eq 0 ]; then note "ALL PASS"; else note "FAILURES PRESENT"; fi
exit $fail
