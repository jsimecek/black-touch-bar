#!/bin/bash
set -euo pipefail

APP_NAME="BlackTouchBar"

echo "==> Building ${APP_NAME}..."
mkdir -p "${APP_NAME}.app/Contents/MacOS" "${APP_NAME}.app/Contents/Resources"
swiftc -O BlackTouchBar.swift \
    -o "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" \
    -framework AppKit
cp Info.plist "${APP_NAME}.app/Contents/Info.plist"
cp "${APP_NAME}.icns" "${APP_NAME}.app/Contents/Resources/${APP_NAME}.icns"

echo "==> Creating DMG..."
rm -rf dmg-staging
mkdir dmg-staging
cp -R "${APP_NAME}.app" dmg-staging/
ln -s /Applications dmg-staging/Applications

rm -f "${APP_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" -srcfolder dmg-staging -ov -format UDZO "${APP_NAME}.dmg"
rm -rf dmg-staging

echo "==> Done! Created ${APP_NAME}.dmg"
