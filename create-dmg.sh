#!/bin/bash
set -euo pipefail

APP_NAME="BlackTouchBar"
STAGING_DIR="dmg-staging"

echo "==> Building ${APP_NAME}..."
mkdir -p "${APP_NAME}.app/Contents/MacOS" "${APP_NAME}.app/Contents/Resources"
swiftc -O BlackTouchBar.swift \
    -o "${APP_NAME}.app/Contents/MacOS/${APP_NAME}" \
    -framework AppKit
cp Info.plist "${APP_NAME}.app/Contents/Info.plist"
cp "${APP_NAME}.icns" "${APP_NAME}.app/Contents/Resources/${APP_NAME}.icns"

echo "==> Creating DMG..."
rm -rf "${STAGING_DIR}"
mkdir "${STAGING_DIR}"
cp -R "${APP_NAME}.app" "${STAGING_DIR}/"
ln -s /Applications "${STAGING_DIR}/Applications"

rm -f "${APP_NAME}.dmg"
hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${APP_NAME}.dmg"
rm -rf "${STAGING_DIR}"

echo "==> Done! Created ${APP_NAME}.dmg"
