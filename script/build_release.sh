#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="CodexTouchBar"
DISPLAY_NAME="Codex Hermes Touch Bar"
WIDGET_PRODUCT_NAME="CodexStatusWidget"
WIDGET_DISPLAY_NAME="AI 工作状态"
BUNDLE_ID="dev.kanyun.CodexHermesTouchBar"
WIDGET_BUNDLE_ID="$BUNDLE_ID.CodexStatusWidget"
DEFAULT_SIGN_IDENTITY="Developer ID Application: Burak Karahan (UPK4SC93AN)"
DEFAULT_NOTARY_PROFILE="desktop-updater-notary"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.5.15}"
VERSION="${VERSION#v}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-$DEFAULT_NOTARY_PROFILE}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
APP_PLUGINS="$APP_CONTENTS/PlugIns"
WIDGET_BUNDLE="$APP_PLUGINS/$WIDGET_PRODUCT_NAME.appex"
WIDGET_CONTENTS="$WIDGET_BUNDLE/Contents"
WIDGET_MACOS="$WIDGET_CONTENTS/MacOS"
WIDGET_BINARY="$WIDGET_MACOS/$WIDGET_PRODUCT_NAME"
WIDGET_INFO_PLIST="$WIDGET_CONTENTS/Info.plist"
WIDGET_ENTITLEMENTS="$ROOT_DIR/Resources/CodexStatusWidget.entitlements"
NOTARY_ZIP="$RELEASE_DIR/$PRODUCT_NAME-v$VERSION-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$PRODUCT_NAME-v$VERSION-macOS.zip"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

swift build \
  --disable-sandbox \
  --configuration release \
  --package-path "$ROOT_DIR"
BUILD_BIN_DIR="$(swift build \
  --disable-sandbox \
  --configuration release \
  --package-path "$ROOT_DIR" \
  --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$PRODUCT_NAME"
BUILD_WIDGET_BINARY="$BUILD_BIN_DIR/$WIDGET_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
rm -f "$NOTARY_ZIP" "$FINAL_ZIP"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$WIDGET_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_WIDGET_BINARY" "$WIDGET_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY" "$WIDGET_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null

cat >"$WIDGET_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>CFBundleDisplayName</key><string>$WIDGET_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key><string>$WIDGET_PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key><string>$WIDGET_BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$WIDGET_PRODUCT_NAME</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleVersion</key><string>47</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSExtension</key>
  <dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>
</dict>
</plist>
PLIST
plutil -lint "$WIDGET_INFO_PLIST" >/dev/null

codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$WIDGET_ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$WIDGET_BUNDLE"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
xcrun notarytool submit \
  "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
rm -f "$NOTARY_ZIP"

echo "$FINAL_ZIP"
