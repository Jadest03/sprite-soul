#!/bin/bash
# SpriteSoul macOS 빌드 스크립트
# 익스포트 후 Info.plist에 NSScreenCaptureUsageDescription 자동 주입

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$PROJECT_DIR/build/SpriteSoul.app"
GODOT="/Applications/Godot.app/Contents/MacOS/Godot"

echo "▶ Godot 익스포트 시작..."
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "macOS" "$APP_PATH"

echo "▶ Info.plist 패치 중..."
plutil -replace NSScreenCaptureUsageDescription \
  -string "SpriteSoul reads the screen to understand what you're doing and react naturally." \
  "$APP_PATH/Contents/Info.plist"

echo "✓ 완료: $APP_PATH"
