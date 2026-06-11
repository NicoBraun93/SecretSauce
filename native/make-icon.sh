#!/bin/bash
# Regenerates the app icon from native/Resources/make-icon.swift.
# Produces native/Resources/AppIcon.icns (used by package-app.sh) and
# native/Resources/icon.png (used in the README). Requires only the
# Xcode Command Line Tools.
set -euo pipefail

NATIVE_DIR="$(cd "$(dirname "$0")" && pwd)"
RES_DIR="$NATIVE_DIR/Resources"
ICONSET="$RES_DIR/AppIcon.iconset"
BIN="$(mktemp -t makeicon)"

echo "Compiling icon generator..."
swiftc -O "$RES_DIR/make-icon.swift" -o "$BIN"

echo "Rendering icon images..."
"$BIN" "$ICONSET" "$RES_DIR/icon.png"

echo "Building AppIcon.icns..."
iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"

# The .iconset dir is an intermediate; keep only the .icns and README png.
rm -rf "$ICONSET" "$BIN"

echo "Done:"
ls -lh "$RES_DIR/AppIcon.icns" "$RES_DIR/icon.png" | awk '{print "  " $5 "  " $9}'
