#!/bin/bash
# Build, sign, notarize, and staple a Developer ID release.
#
# Required environment:
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   APPLE_ID        Apple ID used for notarytool
#   TEAM_ID         Apple Developer team id
#   APP_PASSWORD    app-specific password for notarytool
#
# Usage: ./scripts/notarize.sh
set -euo pipefail

if [ -z "${SIGN_IDENTITY:-}" ] || [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ] || [ -z "${APP_PASSWORD:-}" ]; then
    echo "error: SIGN_IDENTITY, APPLE_ID, TEAM_ID and APP_PASSWORD are required" >&2
    exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIGN_IDENTITY="$SIGN_IDENTITY" ./build.sh release

APP=".build/Semono.app"
ZIP=".build/Semono.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

xcrun stapler staple "$APP"
spctl --assess --type execute --verbose=4 "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarized and stapled: $APP"
