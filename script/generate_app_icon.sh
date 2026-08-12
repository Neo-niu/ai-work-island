#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MASTER="$ROOT_DIR/Resources/AppIcon-master.png"
OUTPUT="$ROOT_DIR/Resources/AppIcon.icns"
ICONSET="$(/usr/bin/mktemp -d)/AppIcon.iconset"

cleanup() {
  /bin/rm -rf "$(/usr/bin/dirname "$ICONSET")"
}
trap cleanup EXIT

/bin/mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  /usr/bin/sips -z "$size" "$size" "$MASTER" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  /usr/bin/sips -z "$retina" "$retina" "$MASTER" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done

/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"
/usr/bin/file "$OUTPUT"
