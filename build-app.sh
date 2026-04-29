#!/usr/bin/env bash
set -euo pipefail

APP_NAME="OFVPN"
BUNDLE_DIR="${BUNDLE_DIR:-.build/${APP_NAME}.app}"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
ICON_SOURCE="${ICON_SOURCE:-Other/applicationIcon1.png}"
ICONSET_DIR="${ICONSET_DIR:-.build/OFVPN.iconset}"

swift build -c release

rm -rf "${BUNDLE_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"
cp ".build/release/FortiVPNMenuBar" "${MACOS_DIR}/FortiVPNMenuBar"

if [[ -f "${ICON_SOURCE}" ]]; then
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}"
  sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  cp "${ICON_SOURCE}" "${ICONSET_DIR}/icon_512x512@2x.png"
  iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_DIR}/OFVPN.icns"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FortiVPNMenuBar</string>
    <key>CFBundleIdentifier</key>
    <string>local.ofvpn.menubar</string>
    <key>CFBundleName</key>
    <string>OFVPN</string>
    <key>CFBundleIconFile</key>
    <string>OFVPN</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.30</string>
    <key>CFBundleVersion</key>
    <string>30</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "Created ${BUNDLE_DIR}"
