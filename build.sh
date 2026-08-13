#!/bin/bash
set -euo pipefail

APP_NAME="Semono"
BUILD_CONFIG="${1:-release}"

case "$BUILD_CONFIG" in
    debug|release) ;;
    *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

# Prefer an Xcode toolchain: the macOS 26+ SDK turns @State into a macro whose
# implementation only ships with Xcode, not CommandLineTools.
for dir in "/Applications/Xcode.app" "/Applications/Xcode-beta.app"; do
    if [ -d "$dir/Contents/Developer" ] && [ -z "${DEVELOPER_DIR:-}" ]; then
        export DEVELOPER_DIR="$dir/Contents/Developer"
        break
    fi
done

echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
BIN_DIR=$(swift build -c "$BUILD_CONFIG" --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"
echo "==> Binary: ${BIN_PATH}"

# Versioning: the release workflow tags before building, so the latest tag is
# the version being shipped. CFBundleVersion follows the project convention
# 2 × minor-version plus the patch number (v1.10 shipped build 20, v1.9.1
# build 19), so it keeps increasing across releases. Falls back to fixed
# values outside a git checkout.
VERSION=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
    VERSION="1.10"
fi
BASE_NUM=$(echo "$VERSION" | awk -F. '{print $2}')
PATCH_NUM=$(echo "$VERSION" | awk -F. '{print ($3 == "" ? 0 : $3)}')
BUILD_NUM=$((2 * BASE_NUM + PATCH_NUM))
if ! [[ "$BUILD_NUM" =~ ^[0-9]+$ ]] || [ "$BUILD_NUM" -lt 20 ]; then
    BUILD_NUM=20
fi
echo "==> Version: ${VERSION} (${BUILD_NUM})"

BUNDLE_DIR=".build/${APP_NAME}.app"
rm -rf "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp "$BIN_PATH" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

# Copy the resident stats helper (serves GPU / power / disk over stdin/stdout).
# A release bundle without it would silently ship zero-valued metrics, so
# that combination is a hard error.
HELPER_PATH="${BIN_DIR}/stats_helper"
if [ -f "$HELPER_PATH" ]; then
    cp "$HELPER_PATH" "${BUNDLE_DIR}/Contents/MacOS/stats_helper"
elif [ "$BUILD_CONFIG" = "release" ]; then
    echo "==> error: stats_helper binary not found" >&2
    exit 1
else
    echo "==> warning: stats_helper binary not found"
fi

# Generate app icon from icon.png
if [ -f "icon.png" ]; then
    ICONSET="$(mktemp -d)/icon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16   icon.png --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32   icon.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32   icon.png --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64   icon.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128 icon.png --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256 icon.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256 icon.png --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512 icon.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512 icon.png --out "$ICONSET/icon_512x512.png" >/dev/null
    # stderr is kept so a broken icon set fails loudly instead of silently.
    iconutil -c icns "$ICONSET" -o "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
fi

# Copy font to app bundle Resources
if [ -f "Sources/${APP_NAME}/Resources/DepartureMono-Regular.otf" ]; then
    cp "Sources/${APP_NAME}/Resources/DepartureMono-Regular.otf" "${BUNDLE_DIR}/Contents/Resources/"
fi

cat > "${BUNDLE_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Semono</string>
    <key>CFBundleIdentifier</key>
    <string>com.semono.app</string>
    <key>CFBundleName</key>
    <string>Semono</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# Ad-hoc code sign the bundle (required for SMAppService launch-at-login;
# replace with a proper Developer ID signature for distribution)
if codesign --force --deep --sign - "${BUNDLE_DIR}" >/dev/null 2>&1; then
    echo "==> Ad-hoc codesigned"
else
    echo "==> warning: ad-hoc codesign failed"
fi

echo "==> App bundle created at ${BUNDLE_DIR}"
echo "==> Run: open ${BUNDLE_DIR}"
