#!/bin/bash
set -e

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
PROJECT="$(dirname "$0")"
OUT="$PROJECT/build/SpriteSoul.app"

pkill -f "SpriteSoul" 2>/dev/null || true

"$GODOT" --headless --path "$PROJECT" --export-release "macOS" "$OUT"

/usr/libexec/PlistBuddy -c \
  "Add :NSScreenCaptureUsageDescription string 'SpriteSoul reads the screen to understand what you are doing and react naturally.'" \
  "$OUT/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c \
  "Set :NSScreenCaptureUsageDescription 'SpriteSoul reads the screen to understand what you are doing and react naturally.'" \
  "$OUT/Contents/Info.plist"

echo "✓ Build complete: $OUT"
open "$OUT"
