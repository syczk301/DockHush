#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-$(cat VERSION)}"
APP='build/DockHush.app'
[ -d "$APP" ] || { echo 'Run scripts/build.sh first.' >&2; exit 1; }
BUILT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
[ "$BUILT_VERSION" = "$VERSION" ] || { echo "Version mismatch: app=$BUILT_VERSION package=$VERSION" >&2; exit 1; }
codesign --verify --strict "$APP"
mkdir -p dist
DMG="dist/DockHush-$VERSION-universal.dmg"
[ ! -e "$DMG" ] || { echo "Already exists: $DMG" >&2; exit 1; }
STAGING="$(mktemp -d "$PWD/build/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/DockHush.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE "$STAGING/LICENSE.txt"
cp docs/INSTALL.txt "$STAGING/INSTALL.txt"
hdiutil create -volname DockHush -srcfolder "$STAGING" -ov -format UDZO "$DMG"
hdiutil verify "$DMG"
(cd dist && shasum -a 256 "DockHush-$VERSION-universal.dmg" > "DockHush-$VERSION-universal.dmg.sha256")
printf 'Packaged: %s/%s\n' "$PWD" "$DMG"
