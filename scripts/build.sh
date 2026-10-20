#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build --package-path "$ROOT" -c release
APP="$ROOT/build/Ultra Transcribe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/UltraTranscribe" "$APP/Contents/MacOS/UltraTranscribe"
cp "$ROOT/packaging/Info.plist" "$APP/Contents/Info.plist"
cp -R "$ROOT/.build/release/UltraTranscribe_UltraTranscribe.bundle" "$APP/Contents/Resources/"
find "$APP" -name __pycache__ -type d -prune -exec rm -rf {} +
install -m 755 "$(command -v uv)" "$APP/Contents/Resources/uv"
if [ -f "$ROOT/packaging/AppIcon.icns" ]; then cp "$ROOT/packaging/AppIcon.icns" "$APP/Contents/Resources/"; fi
# NSAccentColorName names this catalog's AccentColor, so alert buttons, focus rings and text selection are orange.
xcrun actool "$ROOT/packaging/Assets.xcassets" --compile "$APP/Contents/Resources" --platform macosx \
  --minimum-deployment-target "$(plutil -extract LSMinimumSystemVersion raw -o - "$ROOT/packaging/Info.plist")" \
  --output-format human-readable-text --errors --warnings
# A stable identity keeps macOS permissions and Keychain access across rebuilds; fall back to ad-hoc.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
codesign --force --deep --sign "${IDENTITY:--}" --entitlements "$ROOT/packaging/entitlements.plist" "$APP"
printf 'Built %s\n' "$APP"
