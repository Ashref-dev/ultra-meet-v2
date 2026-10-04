#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" -c release
APP="$ROOT/build/Ultra Transcribe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/UltraTranscribe" "$APP/Contents/MacOS/UltraTranscribe"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/.build/release/UltraTranscribe_UltraTranscribe.bundle" "$APP/Contents/Resources/"
cp "$(command -v uv)" "$APP/Contents/Resources/uv"
if [ -f "$ROOT/packaging/AppIcon.icns" ]; then cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/"; fi
# A stable identity keeps macOS permissions and Keychain access across rebuilds; fall back to ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
codesign --force --deep --sign "${IDENTITY:--}" --entitlements "$ROOT/packaging/entitlements.plist" "$APP"
printf 'Built %s\n' "$APP"
