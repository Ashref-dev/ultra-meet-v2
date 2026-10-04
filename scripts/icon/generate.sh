#!/bin/bash
# Regenerates packaging/AppIcon.{png,icns} from the shared logo definition.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BIN="$(mktemp -d)/icon"
swiftc -O "$ROOT/scripts/icon/main.swift" "$ROOT/Sources/Views/LogoGlyph.swift" -o "$BIN"
"$BIN" "$ROOT/packaging/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "$ROOT/packaging/AppIcon.png" --out "$ROOT/packaging/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$ROOT/packaging/AppIcon.png" --out "$ROOT/packaging/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ROOT/packaging/AppIcon.iconset" -o "$ROOT/packaging/AppIcon.icns"
rm -rf "$(dirname "$BIN")"
printf 'Icon generated from LogoGlyph\n'
