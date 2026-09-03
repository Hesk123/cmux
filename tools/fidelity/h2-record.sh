#!/usr/bin/env bash
# Modified 2026-09-03 for the cmux carousel build (cmux-carousel-ui CONTRACT, harness H2; rows 121, 122).
#
# H2's runner. STANDING RULING, team lead 2026-09-03:
#
#   H2 for EVERY unit uses the in-process CarouselFrameRecorder.
#   NEVER `ffmpeg -f avfoundation` over ssh.
#
# Why the ban is mechanical and not advisory. An ssh session cannot answer a TCC
# prompt, so an avfoundation capture does not fail — it HANGS, holding the screen
# capture device open. Two such probes ran for 4.7 hours and blocked every H2 pass on
# the machine for the whole fleet. They were mine, from the row-122 attempt made before
# the no-grant finding, which is exactly why this refusal exists in code rather than in
# a paragraph somebody has to remember.
#
#   h2-record.sh start <tag> <out.mp4>   record the tagged app's own window at 60 fps
#   h2-record.sh extract <in.mp4> <dir>  extract frames for motion_measure.py
#   h2-record.sh guard <command...>      run a command, refusing avfoundation capture
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"

refuse_avfoundation() {
  cat >&2 <<'MSG'
H2 REFUSED: avfoundation screen capture is banned for this build.

  An ssh session cannot answer the Screen Recording TCC prompt, so the capture does not
  fail -- it HANGS holding the capture device, and every other unit's H2 pass blocks
  behind it. Two such probes ran 4.7 hours here and did exactly that.

  Use the in-process recorder instead. It goes through the permission-free
  SCShareableContent.currentProcess path, needs no grant, and records the app's own
  window rather than the whole screen:

      tools/fidelity/h2-record.sh start <tag> <out.mp4>

  which sets CMUX_CAROUSEL_RECORD and lets Sources/Carousel/Fidelity/CarouselFrameRecorder.swift
  do the capture.
MSG
  exit 3
}

case "${1:?usage: start|extract|guard}" in
  start)
    TAG=${2:?tag}; OUT=${3:?output .mp4}
    # The recorder is in-process, so "starting" it means telling the running app to
    # record. Nothing here spawns a capture process of its own.
    if ! pgrep -f "cmux DEV $TAG.app/Contents/MacOS" >/dev/null 2>&1; then
      echo "H2: no running app for tag '$TAG'. Launch it first:" >&2
      echo "  CMUX_CAROUSEL_RECORD=$OUT scripts/reload-carousel.sh" >&2
      exit 1
    fi
    echo "H2: the app for tag '$TAG' is running."
    echo "H2: recording is driven by CMUX_CAROUSEL_RECORD, which must be set BEFORE launch."
    echo "H2: relaunch with:  CMUX_CAROUSEL_RECORD=$OUT scripts/reload-carousel.sh"
    ;;
  extract)
    IN=${2:?input .mp4}; DIR=${3:?frame output dir}
    mkdir -p "$DIR"
    # ffmpeg is fine HERE: decoding a file needs no capture device and no TCC grant.
    # -fps_mode passthrough, because ffmpeg 9 removed -vsync and the old flag yields
    # zero frames while looking like a capture fault.
    ffmpeg -hide_banner -loglevel error -i "$IN" -fps_mode passthrough "$DIR/f_%05d.png"
    echo "H2: extracted $(ls "$DIR" | wc -l | tr -d ' ') frames from $IN"
    ;;
  guard)
    shift
    # A mechanical refusal, so the ban survives a copy-paste from an old runbook.
    for arg in "$@"; do
      case "$arg" in avfoundation|*avfoundation*) refuse_avfoundation ;; esac
    done
    case "$*" in *"-f avfoundation"*) refuse_avfoundation ;; esac
    "$@"
    ;;
  *) sed -n '2,22p' "$0"; exit 2 ;;
esac
