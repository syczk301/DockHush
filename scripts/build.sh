#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/DockHush.app"
mkdir -p build/module-cache build/PolishedHelper.iconset
xcrun swift -module-cache-path build/module-cache scripts/make-icon.swift
python3 scripts/pack-icon.py
for arch in arm64 x86_64; do
  xcrun swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    -module-cache-path build/module-cache Sources/main.swift Sources/DockCompatibility.swift Sources/Localization.swift \
    -o "build/DockHush-$arch" -framework SwiftUI -framework AppKit -framework ApplicationServices
done
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create build/DockHush-arm64 build/DockHush-x86_64 -output "$APP/Contents/MacOS/DockHush"
cp -R Resources/. "$APP/Contents/Resources/"
cp build/DockHush.icns "$APP/Contents/Resources/PolishedHelper.icns"
cp build/StatusMoon.png "$APP/Contents/Resources/StatusMoon.png"
python3 - "$VERSION" "$APP" <<'PY'
import plistlib,sys,pathlib
info=dict(CFBundleIdentifier='io.github.syczk301.DockHush',CFBundleName='DockHush',CFBundleDisplayName='隐坞 DockHush',CFBundleExecutable='DockHush',CFBundleIconFile='PolishedHelper',CFBundlePackageType='APPL',CFBundleShortVersionString=sys.argv[1],CFBundleVersion=sys.argv[1],LSMinimumSystemVersion='13.0',LSUIElement=True,NSHighResolutionCapable=True,CFBundleLocalizations=['en','zh-Hans'],CFBundleDevelopmentRegion='en',NSHumanReadableCopyright='Copyright © 2026 syczk301. MIT License.')
(pathlib.Path(sys.argv[2])/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
if [ "$SIGN_IDENTITY" = '-' ]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"
lipo -info "$APP/Contents/MacOS/DockHush"
printf 'Built: %s/%s\n' "$PWD" "$APP"
