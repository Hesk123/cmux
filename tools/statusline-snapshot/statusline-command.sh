#!/usr/bin/env bash
# Claude Code Status Line — Enhanced with usage bars
# NOTE: No ANSI codes — Claude Code handles its own coloring
input=$(cat)

# --- cmux-carousel-ui row 76: statusline snapshot tee -------------------------
# Modified 2026-09-02 for the cmux carousel build (CONTRACT rows 76, 120, 118).
# Contract: this block MUST NOT change stdout, MUST NOT change the exit status,
# and MUST survive a missing or unwritable snapshot directory.
{
  _cs_root="${CMUX_CAROUSEL_DATA_ROOT:-$HOME/.claude}/statusline-snapshots"
  _cs_sid=$(printf '%s' "$input" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
  # Trust boundary: session_id becomes a filesystem path. A real session_id is a
  # UUID, so REJECT anything not already path-safe rather than sanitizing it into
  # a name no reader would look up. Explicit, not the accidental containment a
  # leading "." happens to provide.
  case "$_cs_sid" in
    ''|.|..)                 _cs_sid="" ;;
    .*)                      _cs_sid="" ;;
    *[!A-Za-z0-9._-]*)       _cs_sid="" ;;
  esac
  if [ -n "$_cs_sid" ]; then
    if mkdir -p "$_cs_root" 2>/dev/null; then
      # Raw payload plus exactly one added top-level key. Underscore-prefixed so
      # it cannot collide with a documented statusline field; every documented
      # field stays at the top level where row 12/13/15's fixtures address it.
      # captured_at is authoritative for row 76's 60 s staleness bound — mtime is
      # a property of the transport, and a mirror that does not preserve it would
      # make every snapshot look permanently fresh, which is the one failure the
      # bound exists to prevent.
      if printf '%s' "$input" | jq -c \
           --argjson t "$(date -u +%s)" \
           --arg h "$(hostname 2>/dev/null || echo unknown)" \
           '. + {_carousel: {captured_at: $t, host: $h, schema: 1}}' \
           > "$_cs_root/.$_cs_sid.tmp" 2>/dev/null \
         && [ -s "$_cs_root/.$_cs_sid.tmp" ]; then
        mv -f "$_cs_root/.$_cs_sid.tmp" "$_cs_root/$_cs_sid.json" 2>/dev/null || \
          rm -f "$_cs_root/.$_cs_sid.tmp" 2>/dev/null
      else
        rm -f "$_cs_root/.$_cs_sid.tmp" 2>/dev/null
      fi
      # 7-day retention, swept at most once a day (row 76).
      _cs_stamp="$_cs_root/.swept"
      if [ -z "$(find "$_cs_stamp" -mtime -1 2>/dev/null)" ]; then
        find "$_cs_root" -name '*.json' -mtime +7 -delete 2>/dev/null
        : > "$_cs_stamp" 2>/dev/null
      fi
    fi
  fi
} >/dev/null 2>&1
# --- end cmux-carousel-ui row 76 tee ------------------------------------------

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')

# Git branch + dirty flag
branch=""
dirty=""
if [ -n "$cwd" ] && git -C "$cwd" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
  if ! git -C "$cwd" --no-optional-locks diff --quiet 2>/dev/null || \
     ! git -C "$cwd" --no-optional-locks diff --cached --quiet 2>/dev/null; then
    dirty="*"
  fi
fi

# Dir label
if [ -n "$session_name" ]; then
  dir_label="$session_name"
elif [ -n "$cwd" ]; then
  dir_label=$(basename "$cwd")
else
  dir_label="~"
fi

# Build circle bar (10 segments)
make_bar() {
  local pct=$1
  local filled=$(( pct * 10 / 100 ))
  local empty=$(( 10 - filled ))
  local bar=""
  for i in $(seq 1 $filled); do bar="${bar}●"; done
  for i in $(seq 1 $empty); do bar="${bar}○"; done
  echo -n "$bar"
}

# Context percentage + emoji
ctx_emoji=""
ctx_pct_int=""
ctx_bar=""
if [ -n "$used_pct" ]; then
  ctx_pct_int=$(printf "%.0f" "$used_pct" 2>/dev/null || echo "$used_pct")
  ctx_bar=$(make_bar "$ctx_pct_int")
  if [ "$ctx_pct_int" -ge 90 ]; then ctx_emoji="🔥"
  elif [ "$ctx_pct_int" -ge 75 ]; then ctx_emoji="⚠️"
  elif [ "$ctx_pct_int" -ge 50 ]; then ctx_emoji="🤙"
  else ctx_emoji="✅"
  fi
fi

# Model short name
model_short="${model#Claude }"

# Build output
output=""
[ -n "$model_short" ] && output="$model_short"

if [ -n "$ctx_emoji" ] && [ -n "$ctx_pct_int" ]; then
  output="$output | $ctx_emoji $ctx_pct_int%"
fi

if [ -n "$branch" ]; then
  output="$output | $dir_label ($branch$dirty)"
else
  output="$output | $dir_label"
fi

# Add bar on same line
if [ -n "$ctx_bar" ]; then
  output="$output | $ctx_bar"
fi

echo -n "$output"
