#!/usr/bin/env bash
# Generate every macOS AppIcon size (and a standalone .icns for the DMG volume
# icon) from a single 1024x1024 source PNG.
#
# Usage:  scripts/make-appicon.sh path/to/logo-1024.png
#
# Writes the resized PNGs into Lumos/Assets.xcassets/AppIcon.appiconset/ and a
# Lumos.icns next to it (used to brand the .dmg volume — see release.yml).
set -euo pipefail

SRC="${1:?Usage: make-appicon.sh <1024x1024 source.png>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$ROOT/Lumos/Assets.xcassets/AppIcon.appiconset"

[ -f "$SRC" ] || { echo "error: source image not found: $SRC" >&2; exit 1; }

for size in 16 32 64 128 256 512 1024; do
  sips -s format png -z "$size" "$size" "$SRC" --out "$SET/icon_${size}.png" >/dev/null
done
echo "Wrote PNGs to $SET"

# Build a .icns (for the DMG volume icon) from a temporary iconset.
ICONSET="$(mktemp -d)/Lumos.iconset"
mkdir -p "$ICONSET"
cp "$SET/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$SET/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$SET/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$SET/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$SET/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$SET/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$SET/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$SET/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$SET/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$SET/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$ROOT/Lumos/Lumos.icns"
echo "Wrote $ROOT/Lumos/Lumos.icns"
