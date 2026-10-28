#!/bin/bash
# Convert the chosen master artwork into all native macOS icon representations.
set -euo pipefail
cd "$(dirname "$0")/.."
source_image=Resources/AppIcon.png
iconset="$PWD/.build/AppIcon.iconset"
mkdir -p "$iconset"
for dimensions in 16 32 128 256 512; do
  sips -z "$dimensions" "$dimensions" "$source_image" --out "$iconset/icon_${dimensions}x${dimensions}.png" >/dev/null
  double=$((dimensions * 2))
  sips -z "$double" "$double" "$source_image" --out "$iconset/icon_${dimensions}x${dimensions}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
