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
# The build has to be requested explicitly: `--show-bin-path` only reports where
# the products *would* go, so a script that just asks for the path and then
# copies from it happily repackages whatever binary happens to be lying around
# from an earlier build.
swift build -c "$BUILD_CONFIG"
BIN_DIR=$(swift build -c "$BUILD_CONFIG" --show-bin-path)
BIN_PATH="${BIN_DIR}/${APP_NAME}"
echo "==> Binary: ${BIN_PATH}"
if [ ! -f "$BIN_PATH" ]; then
    echo "==> error: the build produced no binary at ${BIN_PATH}" >&2
    exit 1
fi

# Versioning: the release workflow tags before building, so the latest tag is
# the marketing version being shipped. CFBundleVersion is a separate monotonic
# build number — a commit count (or CI_BUILD_NUMBER) — so v1.13.2 and v1.14.0
# cannot collide and patch releases sort after the minor they patch.
#
# The previous scheme accepted only x.y and derived 2*minor+patch; a v1.9.1
# tag fell back to 1.10, and patch >= 2 collided with the next minor.
VERSION_RAW=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
VERSION="${VERSION_RAW#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    VERSION="0.0.0"
    echo "==> warning: no vX.Y[.Z] tag found; using ${VERSION}" >&2
fi

if [ "$BUILD_CONFIG" = "release" ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [ -n "$(git status --porcelain)" ]; then
        echo "==> error: release build from a dirty worktree; commit or stash first" >&2
        exit 1
    fi
fi

if [ -n "${BUILD_NUMBER:-}" ]; then
    BUILD_NUM="$BUILD_NUMBER"
else
    # Offset above the legacy 2*minor+patch builds (v1.13 shipped build 26)
    # so an update from the old scheme is still seen as newer by the system.
    BUILD_NUM=$((1000 + $(git rev-list --count HEAD 2>/dev/null || echo 1)))
fi
if ! [[ "$BUILD_NUM" =~ ^[0-9]+$ ]] || [ "$BUILD_NUM" -lt 1 ]; then
    BUILD_NUM=1
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
HELPER_DST="${BUNDLE_DIR}/Contents/MacOS/stats_helper"
if [ -f "$HELPER_PATH" ]; then
    cp "$HELPER_PATH" "$HELPER_DST"
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

# Smoke-test the resident helper's protocol before signing the bundle. A
# release with a helper that cannot answer `hello` would silently ship
# unavailable GPU/power/disk readings.
if [ -x "$HELPER_DST" ]; then
    HELLO=$(printf '1 hello\n' | "$HELPER_DST" 2>/dev/null | head -1 || true)
    if [ "$HELLO" != "1 hello 2" ]; then
        echo "==> error: stats_helper protocol smoke test failed (got: ${HELLO:-nothing})" >&2
        exit 1
    fi
    echo "==> stats_helper protocol OK"
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
    <key>CFBundleDisplayName</key>
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
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# Sign the bundle. Ad-hoc signing is enough for local runs, but SMAppService
# login items and Gatekeeper distribution need a Developer ID Application
# identity with Hardened Runtime. Sign the nested helper first, then the app;
# `--deep` is kept for the ad-hoc path only.
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Signing with Developer ID: ${SIGN_IDENTITY}"
    if [ -f "$HELPER_DST" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$HELPER_DST"
    fi
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "${BUNDLE_DIR}"
else
    if ! codesign --force --deep --sign - "${BUNDLE_DIR}" >/dev/null 2>&1; then
        echo "==> error: ad-hoc codesign failed" >&2
        exit 1
    fi
    echo "==> Ad-hoc codesigned (set SIGN_IDENTITY for a Developer ID build)"
fi

plutil -lint "${BUNDLE_DIR}/Contents/Info.plist"
codesign --verify --deep --strict "${BUNDLE_DIR}"
echo "==> Signature verified"

echo "==> App bundle created at ${BUNDLE_DIR}"
echo "==> Run: open ${BUNDLE_DIR}"
