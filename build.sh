#!/bin/bash
set -euo pipefail

APP_NAME="Semono"
BUILD_CONFIG="${1:-release}"

echo "==> Building ${APP_NAME} (${BUILD_CONFIG})..."
swift build -c "$BUILD_CONFIG"

BIN_DIR=$(swift build -c "$BUILD_CONFIG" --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"
echo "==> Binary: ${BIN_PATH}"

BUNDLE_DIR=".build/${APP_NAME}.app"
rm -rf "$BUNDLE_DIR"
mkdir -p "${BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${BUNDLE_DIR}/Contents/Resources"

cp "$BIN_PATH" "${BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

# Copy helpers
HELPER_PATH="${BIN_DIR}/power_helper"
if [ -f "$HELPER_PATH" ]; then
    cp "$HELPER_PATH" "${BUNDLE_DIR}/Contents/MacOS/power_helper"
fi

GPU_HELPER_PATH="${BIN_DIR}/gpu_helper"
if [ -f "$GPU_HELPER_PATH" ]; then
    cp "$GPU_HELPER_PATH" "${BUNDLE_DIR}/Contents/MacOS/gpu_helper"
fi

DISK_HELPER_PATH="${BIN_DIR}/disk_helper"
if [ -f "$DISK_HELPER_PATH" ]; then
    cp "$DISK_HELPER_PATH" "${BUNDLE_DIR}/Contents/MacOS/disk_helper"
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
    iconutil -c icns "$ICONSET" -o "${BUNDLE_DIR}/Contents/Resources/AppIcon.icns" 2>/dev/null
    rm -rf "$(dirname "$ICONSET")"
fi

# Copy font to app bundle Resources
if [ -f "Sources/${APP_NAME}/Resources/DepartureMono-Regular.otf" ]; then
    cp "Sources/${APP_NAME}/Resources/DepartureMono-Regular.otf" "${BUNDLE_DIR}/Contents/Resources/"
fi

cat > "${BUNDLE_DIR}/Contents/Info.plist" << 'PLIST'
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
    <string>1.3</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

echo "==> App bundle created at ${BUNDLE_DIR}"
echo "==> Run: open ${BUNDLE_DIR}"
