#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Info.plist")"
APP="$ROOT/dist/VibePulse.app"
DMG="$ROOT/dist/VibePulse-${VERSION}-macOS-arm64.dmg"
STAGING="$ROOT/dist/dmg-staging"

"$ROOT/build-app.sh"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/VibePulse.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "VibePulse ${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"
(cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")

echo "Built $DMG"
