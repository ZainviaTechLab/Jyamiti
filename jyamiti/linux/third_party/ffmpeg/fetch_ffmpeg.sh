#!/usr/bin/env bash
# UNVERIFIED (not run) -- same caveat as native_camera/external_compositor.cc
# in this same directory tree. Downloads the static Linux ffmpeg build this
# project bundles for Math Pad's board+voice recording feature (see
# MathPadRecordingService). ffmpeg itself isn't committed to git (~80MB
# binary, GPLv3 -- see NOTICE.txt) -- run this once after cloning, before
# building for Linux. Mirrors windows/third_party/ffmpeg/fetch_ffmpeg.ps1
# and macos/third_party/ffmpeg/fetch_ffmpeg.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARBALL="$SCRIPT_DIR/ffmpeg-release-amd64-static.tar.xz"
DEST="$SCRIPT_DIR/ffmpeg"

if [ -f "$DEST" ]; then
  echo "ffmpeg already present at $DEST -- nothing to do."
  exit 0
fi

echo "Downloading ffmpeg (johnvansickle.com static amd64 build)..."
curl -L -o "$TARBALL" \
  "https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz"

echo "Extracting ffmpeg..."
EXTRACT_DIR="$SCRIPT_DIR/_extract_tmp"
rm -rf "$EXTRACT_DIR"
mkdir -p "$EXTRACT_DIR"
tar -xf "$TARBALL" -C "$EXTRACT_DIR"

FFMPEG_BIN="$(find "$EXTRACT_DIR" -maxdepth 2 -name ffmpeg -type f | head -n1)"
if [ -z "$FFMPEG_BIN" ]; then
  echo "Could not find an ffmpeg binary inside the downloaded archive." >&2
  exit 1
fi
cp "$FFMPEG_BIN" "$DEST"
chmod +x "$DEST"

rm -rf "$EXTRACT_DIR" "$TARBALL"
echo "Done -- ffmpeg installed at $DEST"
