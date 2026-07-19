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
    <string>1.1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> App bundle created at ${BUNDLE_DIR}"
echo "==> Run: open ${BUNDLE_DIR}"
