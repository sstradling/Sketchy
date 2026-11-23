#!/usr/bin/env bash
# Render the README wordmark, docs/images/header.gif, with Sketchy itself.
#
# Usage:
#   scripts/render-header.sh
#
# The leading "S" is a white paper sticker (StickerBacking). The "!" boils
# (AnimatedRoughView pinned to one step per frame). The other six letters are
# static. HeaderBannerRenderTests rasterizes the frames on a simulator and
# gifski assembles them. Seeds are fixed in Tests/SketchyTests/Docs/HeaderBannerSpec.swift,
# so two consecutive runs produce a byte-identical GIF.
#
# Like DocsGalleryTests, the render test skips unless TEST_RUNNER_RENDER_HEADER=1
# reaches the test process. This script sets it on the booted simulator with
# `simctl spawn ... launchctl setenv` and clears it on exit.
#
# Font: Bungee (OFL) is downloaded once into build/header and checked against a
# pinned SHA-256. Set HEADER_FONT_FILE to use a copy you already have.
#
# Budgets, enforced here: GIF under 10 MB (hard), under 1 MB (target; the
# script lowers gifski quality to reach it and fails only past the hard limit).
#
# Requirements on PATH: gifski. Set SKETCHY_SIMULATOR_UDID to pick a simulator.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

WORK="$ROOT/build/header"
FRAMES="$WORK/frames"
LOG="$ROOT/build/header-render.log"
DERIVED="$ROOT/build/DerivedData"
RESULT="$ROOT/build/header.xcresult"
OUTPUT="$ROOT/docs/images/header.gif"
FONT_URL="https://github.com/google/fonts/raw/main/ofl/bungee/Bungee-Regular.ttf"
FONT_SHA256="c4f5361ce120af3e6b9156d0bf379fa19cda2ea0cd18ac01fd99596c6bf66e3f"
FONT_FILE="${HEADER_FONT_FILE:-$WORK/Bungee-Regular.ttf}"

MAX_GIF=$((10 * 1024 * 1024))
TARGET_GIF=$((1024 * 1024))
XCODEBUILD_TIMEOUT=1200

# Same encoder code path on every run.
export RAYON_NUM_THREADS=1

if ! command -v gifski >/dev/null 2>&1; then
  echo "Missing 'gifski'. Install with: brew install gifski"
  exit 1
fi

mkdir -p "$WORK"
rm -rf "$FRAMES" "$RESULT"

if [[ ! -f "$FONT_FILE" ]]; then
  echo "Downloading Bungee-Regular.ttf"
  curl -fsSL -o "$FONT_FILE" "$FONT_URL"
fi
actual_sha="$(shasum -a 256 "$FONT_FILE" | awk '{ print $1 }')"
if [[ "$actual_sha" != "$FONT_SHA256" ]]; then
  echo "error: $FONT_FILE has SHA-256 $actual_sha, expected $FONT_SHA256."
  exit 1
fi

# Run a command in its own process group, logging to `logfile`.
# Exit 124 if it is still running after `seconds`, after killing the group.
run_with_timeout() {
  local seconds="$1"
  local logfile="$2"
  shift 2
  perl - "$seconds" "$logfile" "$@" <<'PERL'
use strict;
use warnings;
my $seconds = shift @ARGV;
my $logfile = shift @ARGV;
my $pid = fork();
die "fork: $!" unless defined $pid;
if ($pid == 0) {
    setpgrp(0, 0);
    open my $log, ">", $logfile or die "open $logfile: $!";
    open STDOUT, ">&", $log or die $!;
    open STDERR, ">&", $log or die $!;
    exec @ARGV or die "exec: $!";
}
my $timed_out = 0;
local $SIG{ALRM} = sub { $timed_out = 1; kill "TERM", -$pid; };
alarm $seconds;
waitpid($pid, 0);
my $status = $?;
alarm 0;
if ($timed_out) {
    sleep 2;
    kill "KILL", -$pid;
    waitpid($pid, 0);
    exit 124;
}
if ($status & 127) {
    exit 128 + ($status & 127);
}
exit($status >> 8);
PERL
}

# iPhone 16 Pro on iOS 18.6, the simulator render-docs.sh uses.
if [[ -n "${SKETCHY_SIMULATOR_UDID:-}" ]]; then
  UDID="$SKETCHY_SIMULATOR_UDID"
else
  UDID="$(
    xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data.get("devices", {}).items():
    if "iOS-18-6" not in runtime:
        continue
    for device in devices:
        if device.get("isAvailable") and device.get("name") == "iPhone 16 Pro":
            print(device["udid"])
            sys.exit(0)
sys.stderr.write("No available iPhone 16 Pro simulator on iOS 18.6\n")
sys.exit(1)
'
  )"
fi
DESTINATION="platform=iOS Simulator,id=${UDID}"

clear_render_env() {
  local name
  for name in TEST_RUNNER_RENDER_HEADER RENDER_HEADER \
    TEST_RUNNER_HEADER_OUTPUT HEADER_OUTPUT TEST_RUNNER_HEADER_FONT HEADER_FONT; do
    xcrun simctl spawn "$UDID" launchctl unsetenv "$name" >/dev/null 2>&1 || true
  done
}
trap clear_render_env EXIT

xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b
for prefix in TEST_RUNNER_ ""; do
  xcrun simctl spawn "$UDID" launchctl setenv "${prefix}RENDER_HEADER" 1
  xcrun simctl spawn "$UDID" launchctl setenv "${prefix}HEADER_OUTPUT" "$FRAMES"
  xcrun simctl spawn "$UDID" launchctl setenv "${prefix}HEADER_FONT" "$FONT_FILE"
done

echo "Rendering header frames on ${DESTINATION} (timeout ${XCODEBUILD_TIMEOUT}s)"
echo "Log: $LOG"
set +e
run_with_timeout "$XCODEBUILD_TIMEOUT" "$LOG" \
  xcodebuild test \
  -scheme Sketchy \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED" \
  -resultBundlePath "$RESULT" \
  -only-testing:SketchyTests/HeaderBannerRenderTests \
  -parallel-testing-enabled NO \
  -enableCodeCoverage NO
status=$?
set -e
if [[ "$status" -eq 124 ]]; then
  echo "error: xcodebuild exceeded ${XCODEBUILD_TIMEOUT}s and was killed. Log: $LOG"
  exit 124
fi
if [[ "$status" -ne 0 ]]; then
  echo "error: xcodebuild exited $status. Log: $LOG"
  exit "$status"
fi
if [[ ! -f "$FRAMES/manifest.json" ]]; then
  echo "error: HeaderBannerRenderTests did not write $FRAMES/manifest.json."
  echo "The test is skipped unless TEST_RUNNER_RENDER_HEADER=1 reaches the runner. Log: $LOG"
  exit 1
fi

read -r FPS WIDTH HEIGHT FRAME_COUNT < <(python3 - "$FRAMES/manifest.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
print(m["fps"], m["pixelWidth"], m["pixelHeight"], m["frameCount"])
PY
)

frame_list=()
while IFS= read -r frame; do
  frame_list+=("$frame")
done < <(find "$FRAMES" -name 'frame-*.png' | sort)
if [[ "${#frame_list[@]}" -ne "$FRAME_COUNT" ]]; then
  echo "error: expected $FRAME_COUNT frames in $FRAMES, found ${#frame_list[@]}."
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT")"
quality=100
while true; do
  gifski \
    --quiet \
    --fps "$FPS" \
    --width "$WIDTH" \
    --height "$HEIGHT" \
    --quality "$quality" \
    --repeat 0 \
    --no-sort \
    -o "$OUTPUT" \
    "${frame_list[@]}"
  size="$(stat -f%z "$OUTPUT")"
  echo "header.gif ${size} bytes at gifski quality ${quality}"
  if [[ "$size" -le "$TARGET_GIF" ]]; then
    break
  fi
  quality=$((quality - 10))
  if [[ "$quality" -lt 50 ]]; then
    echo "warning: header.gif stays above the 1 MB target at gifski quality 50."
    break
  fi
done

if [[ "$size" -gt "$MAX_GIF" ]]; then
  echo "error: header.gif is ${size} bytes (hard limit ${MAX_GIF})."
  exit 1
fi
echo "Wrote ${OUTPUT#"$ROOT"/}: ${WIDTH}x${HEIGHT}, ${FRAME_COUNT} frames at ${FPS} fps, ${size} bytes"
