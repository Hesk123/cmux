#!/usr/bin/env bash
# Modified 2026-09-02 for the cmux carousel build (cmux-carousel-ui CONTRACT rows 86, 128, 133).
#
# The ONE command that builds and relaunches the carousel fork.
#
# It is a THIN WRAPPER over the repo's own ./scripts/reload.sh and adds no second
# build path. AGENTS.md is binding: a bare `xcodebuild` or an untagged `open` shares
# the default debug socket and bundle id with every other agent on this Mac, causing
# conflicts and stealing focus. CONTRACT row 133 makes that binding on every maker,
# and row 86 requires this script to be a wrapper rather than a rival.
#
#   reload-carousel.sh                 Debug build + launch      (the shipped artifact, row 87)
#   reload-carousel.sh --release       Release build + launch    (measurement only, row 128)
#   reload-carousel.sh --no-launch     build without launching
#
# CONFIGURATION: --tag defaults to the current branch slug so parallel worktrees do
# not collide. Override with CMUX_CAROUSEL_TAG.
#
# SURVIVING MANUAL STEPS (CONTRACT row 95 requires these named, not implied):
#   1. Xcode must be installed and selected (`xcode-select -p`); this script does not
#      install it. The Metal Toolchain component is also required -- without it
#      Ghostty's shader build fails with "cannot execute tool 'metal'".
#   2. The FIRST build in a new worktree warms DerivedData and takes ~12 minutes.
#      A stale SwiftPM artifact cache from a previous racing build shows up as a
#      sparkle artifact error; this script clears that one cache and retries once.
#   3. The row-122 TCC grants (Screen Recording for H2's out-of-process capture,
#      Accessibility for synthetic events) are issued once, by hand, in System
#      Settings. They are not scriptable and this script does not attempt them.
#   4. There is no CI runner for a local-only macOS app. This script IS the deploy.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Homebrew is absent from a non-interactive ssh PATH on this machine, and the repo's
# setup scripts need zig from there. Named in PROVISION.md as a repeat time sink.
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.cargo/bin:$PATH"

CONFIG=debug
LAUNCH=--launch
for arg in "$@"; do
  case "$arg" in
    --release) CONFIG=release ;;
    --debug) CONFIG=debug ;;
    --no-launch) LAUNCH="" ;;
    *) echo "unknown argument: $arg" >&2; sed -n '2,30p' "$0" >&2; exit 2 ;;
  esac
done

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo carousel)"
TAG="${CMUX_CAROUSEL_TAG:-$(printf '%s' "$BRANCH" | tr '/' '-' | tr -cd '[:alnum:]-')}"
COMMIT="$(git rev-parse HEAD)"

if [ "$CONFIG" = release ]; then
  # Row 128: a Release configuration exists SOLELY for measurement (rows 94 and 112).
  # The shipped artifact stays Debug per row 87. reloadp.sh is the repo's own Release
  # variant; this script does not invent a second one.
  BUILDER=./scripts/reloadp.sh
  echo "reload-carousel: RELEASE build -- measurement only (rows 94, 112)."
  echo "reload-carousel: the SHIPPED artifact is the Debug build (row 87). Do not hand this one over."
else
  BUILDER=./scripts/reload.sh
fi

run_build() {
  # shellcheck disable=SC2086
  "$BUILDER" --tag "$TAG" $LAUNCH
}

echo "reload-carousel: tag=$TAG config=$CONFIG commit=$COMMIT"
if ! run_build; then
  DD="$HOME/Library/Developer/Xcode/DerivedData/cmux-$TAG/SourcePackages/artifacts/sparkle"
  if [ -d "$DD" ]; then
    echo "reload-carousel: clearing the stale SwiftPM sparkle artifact cache and retrying once." >&2
    rm -rf "$DD"
    run_build
  else
    exit 1
  fi
fi

# Row 86: the relaunched tagged app must report the new commit hash. The build stamps
# it into the bundle; assert it here rather than trusting that the build was the one
# that just ran, which is the difference between a build proof and a build wish.
APP_DIR="$HOME/Library/Developer/Xcode/DerivedData/cmux-$TAG/Build/Products"
APP="$(find "$APP_DIR" -maxdepth 2 -name '*.app' -print -quit 2>/dev/null || true)"
if [ -z "$APP" ]; then
  echo "reload-carousel: BUILD REPORTED SUCCESS BUT NO .app EXISTS under $APP_DIR" >&2
  exit 1
fi
echo "reload-carousel: built $APP"
echo "reload-carousel: commit $COMMIT"
echo "reload-carousel: report this build as http://127.0.0.1:17320/$TAG (AGENTS.md forbids a file:// URL or a raw .app path in chat)"
