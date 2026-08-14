#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
ZIP_PATH="$DIR/ffmpeg-mac.zip"
EXE_PATH="$DIR/ffmpeg"

if [ -f "$EXE_PATH" ]; then
    echo "ffmpeg already exists at $EXE_PATH"
    exit 0
fi

echo "Downloading macOS ffmpeg static binary from evermeet.cx..."
curl -L -o "$ZIP_PATH" "https://evermeet.cx/ffmpeg/getrelease/zip"

echo "Extracting ffmpeg..."
unzip -o -q "$ZIP_PATH" -d "$DIR"

echo "Removing quarantine attribute..."
xattr -d com.apple.quarantine "$EXE_PATH" || true

echo "Cleaning up..."
rm "$ZIP_PATH"

echo "Done! ffmpeg is ready at $EXE_PATH"
