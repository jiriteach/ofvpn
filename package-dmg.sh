#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OFVPN"
APP_PATH=".build/${APP_NAME}.app"
INFO_PLIST="${APP_PATH}/Contents/Info.plist"

if [[ ! -d "${APP_PATH}" ]]; then
  ./build-app.sh
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
DMG_ROOT=".build/dmg-root"
DMG_PATH=".build/${APP_NAME}-${VERSION}.dmg"

rm -rf "${DMG_ROOT}" "${DMG_PATH}"
mkdir -p "${DMG_ROOT}"
cp -R "${APP_PATH}" "${DMG_ROOT}/"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
  -volname "${APP_NAME} ${VERSION}" \
  -srcfolder "${DMG_ROOT}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "Created ${DMG_PATH}"
