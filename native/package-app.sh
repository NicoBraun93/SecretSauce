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

# Embed Sparkle.framework (auto-update). The SPM binary artifact ships a
# universal (arm64 + x86_64) slice, so no lipo is needed for the framework.
# ditto preserves the framework's symlinks, nested helpers (Autoupdate,
# Updater.app, XPCServices) and their code signatures.
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
SPARKLE_FW="$(find "$NATIVE_DIR/.build/artifacts" -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
[ -z "$SPARKLE_FW" ] && SPARKLE_FW="$(find "$NATIVE_DIR/.build/artifacts" -type d -name Sparkle.framework 2>/dev/null | head -1)"
if [ -z "$SPARKLE_FW" ]; then
  echo "ERROR: Sparkle.framework not found under .build/artifacts — run 'swift build' first." >&2
  exit 1
fi
echo "Embedding Sparkle.framework from $SPARKLE_FW"
/usr/bin/ditto "$SPARKLE_FW" "$FRAMEWORKS_DIR/Sparkle.framework"

# Sparkle's install name is @rpath/Sparkle.framework/...; point @rpath at the
# bundle's Frameworks dir so the embedded copy is found at launch.
/usr/bin/install_name_tool -add_rpath @executable_path/../Frameworks \
  "$APP_DIR/Contents/MacOS/SecretSauce" 2>/dev/null || true

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
    <!-- Sparkle auto-update. Feed points at the newest GitHub release's
         appcast.xml asset (generated + EdDSA-signed in CI). The public key
         verifies update signatures; its private half is a GitHub Actions
         secret (SPARKLE_ED_PRIVATE_KEY). -->
    <key>SUFeedURL</key>
    <string>https://github.com/NicoBraun93/SecretSauce/releases/latest/download/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>Lcx5M9YPCHIrao4fqZaSwOjVC+0ITGQwB/0/zBG6CRU=</string>
    <!-- ip-api.com's free geo endpoint is HTTP-only; ATS blocks plain HTTP
         without this scoped exception (used by the Network Monitor map). -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>ip-api.com</key>
            <dict>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST

# Ad-hoc sign so the bundle runs on Apple Silicon; still unsigned for Gatekeeper,
# so first launch needs the same xattr workaround as the Electron builds.
# Sign inside-out: the embedded Sparkle.framework (and its nested Autoupdate /
# Updater.app / XPCServices) first, then the app bundle. Sparkle verifies
# updates via the EdDSA (SUPublicEDKey) signature, so ad-hoc signing is fine.
/usr/bin/codesign --force --deep --sign - "$FRAMEWORKS_DIR/Sparkle.framework"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

echo "Done: $APP_DIR"
du -sh "$APP_DIR"
