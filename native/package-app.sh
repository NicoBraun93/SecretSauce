#!/bin/bash
# Builds the native SwiftUI app and bundles it as release/SecretSauce.app.
# Produces a universal binary (arm64 + x86_64) — one .app for all Macs.
# Requires only the Xcode Command Line Tools (no full Xcode).
set -euo pipefail

NATIVE_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$NATIVE_DIR")"
VERSION="$(sed -n 's/^[[:space:]]*"version":[[:space:]]*"\([^"]*\)".*/\1/p' "$REPO_DIR/package.json" | head -1)"
VERSION="${VERSION:-1.0.0}"

APP_DIR="$REPO_DIR/release/SecretSauce.app"

# Multi-arch `swift build --arch a --arch b` requires full Xcode (xcbuild),
# so build each slice separately and lipo them into a universal binary.
echo "Building SecretSauce $VERSION (universal release binary)..."
cd "$NATIVE_DIR"
swift build -c release --arch arm64
swift build -c release --arch x86_64

ARM_BIN="$(swift build -c release --arch arm64 --show-bin-path)/SecretSauce"
X64_BIN="$(swift build -c release --arch x86_64 --show-bin-path)/SecretSauce"

echo "Assembling $APP_DIR ..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/usr/bin/lipo -create "$ARM_BIN" "$X64_BIN" -output "$APP_DIR/Contents/MacOS/SecretSauce"

# App icon. Build it if missing (e.g. on a fresh CI checkout).
ICON_SRC="$NATIVE_DIR/Resources/AppIcon.icns"
if [ ! -f "$ICON_SRC" ]; then
  echo "AppIcon.icns missing — generating it..."
  bash "$NATIVE_DIR/make-icon.sh"
fi
cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>SecretSauce</string>
    <key>CFBundleDisplayName</key>
    <string>SecretSauce</string>
    <key>CFBundleIdentifier</key>
    <string>net.nicobraun.secretsauce</string>
    <key>CFBundleExecutable</key>
    <string>SecretSauce</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© Nico Braun</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so the bundle runs on Apple Silicon; still unsigned for Gatekeeper,
# so first launch needs the same xattr workaround as the Electron builds.
/usr/bin/codesign --force --sign - "$APP_DIR"

echo "Done: $APP_DIR"
du -sh "$APP_DIR"
