#!/bin/bash
# Renders docs/cover.png from the shared logo definition.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
swiftc -O "$ROOT/scripts/cover/main.swift" "$ROOT/Sources/Views/LogoGlyph.swift" -o "$WORK/cover"
mkdir -p "$ROOT/docs"
"$WORK/cover" "$ROOT/docs/cover.png"
rm -rf "$WORK"
printf 'Cover rendered to docs/cover.png\n'
