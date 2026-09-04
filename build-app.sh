#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP_NAME="Pi Web"
APP_VERSION="${APP_VERSION:-1.0.1}"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ICON_SOURCE="$ROOT/Resources/PiWeb.icns"

if [[ ! "$APP_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Invalid APP_VERSION: $APP_VERSION (expected x.y.z)" >&2
    exit 1
fi

cd "$ROOT"
swift build -c release
BUILD_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/PiWeb" "$APP_DIR/Contents/MacOS/PiWeb"
cp "$ICON_SOURCE" "$APP_DIR/Contents/Resources/PiWeb.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleDisplayName</key>
    <string>Pi Web</string>
    <key>CFBundleExecutable</key>
    <string>PiWeb</string>
    <key>CFBundleIconFile</key>
    <string>PiWeb.icns</string>
    <key>CFBundleIdentifier</key>
    <string>com.xrsec.piweb</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Pi Web</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>11.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Pi Web 需要访问您的下载文件夹以运行相关服务和读写文件。</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>Pi Web 需要访问您的文稿文件夹以运行相关服务和读写文件。</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Pi Web 需要访问您的桌面文件夹以运行相关服务和读写文件。</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

if [[ "${INSTALL_APP:-1}" == "1" ]]; then
    ditto "$APP_DIR" "/Applications/$APP_NAME.app"
fi

echo "$APP_DIR"
