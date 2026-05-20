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

# ad-hoc sign with entitlements so macOS allows file access (Downloads, user-selected)
ENTITLEMENTS="$(mktemp).plist"
cat > "$ENTITLEMENTS" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.files.downloads.read-write</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$OUT"
rm "$ENTITLEMENTS"

echo "✓ Build complete: $OUT"
open "$OUT"
