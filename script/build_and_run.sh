#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="CodexTouchBar"
DISPLAY_NAME="Codex Hermes Touch Bar"
PROCESS_NAME="$PRODUCT_NAME"
BUNDLE_ID="dev.kanyun.CodexHermesTouchBar"
WIDGET_PRODUCT_NAME="CodexStatusWidget"
WIDGET_DISPLAY_NAME="AI 工作状态"
WIDGET_BUNDLE_ID="$BUNDLE_ID.CodexStatusWidget"
MIN_SYSTEM_VERSION="13.0"
DEFAULT_SIGN_IDENTITY=""
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
ADHOC_REQUIREMENT="designated => identifier \"$BUNDLE_ID\""
WIDGET_ADHOC_REQUIREMENT="designated => identifier \"$WIDGET_BUNDLE_ID\""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SCRATCH_DIR="${CODEX_HERMES_BUILD_DIR:-/tmp/codex-hermes-touch-bar-build}"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
INSTALLED_APP_BUNDLE="/Applications/$DISPLAY_NAME.app"
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
INSTALLED_WIDGET_BUNDLE="$INSTALLED_APP_BUNDLE/Contents/PlugIns/$WIDGET_PRODUCT_NAME.appex"
SIGNING_BUNDLE="$(/usr/bin/mktemp -d)/$DISPLAY_NAME.app"
SIGNING_WIDGET_BUNDLE="$SIGNING_BUNDLE/Contents/PlugIns/$WIDGET_PRODUCT_NAME.appex"

cleanup() {
  /bin/rm -rf "$(/usr/bin/dirname "$SIGNING_BUNDLE")"
}
trap cleanup EXIT

stop_running_app() {
  if ! /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    return
  fi

  /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
      return
    fi
    sleep 0.2
  done

  pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
}

stop_running_app

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

swift build --disable-sandbox --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_DIR"
BUILD_BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$PRODUCT_NAME"
BUILD_WIDGET_BINARY="$BUILD_BIN_DIR/$WIDGET_PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$WIDGET_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$BUILD_WIDGET_BINARY" "$WIDGET_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY" "$WIDGET_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.5.7</string>
  <key>CFBundleVersion</key>
  <string>39</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>AI 工作状态</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>codexhermestouchbar</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

cat >"$WIDGET_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleDisplayName</key>
  <string>$WIDGET_DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$WIDGET_PRODUCT_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$WIDGET_BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$WIDGET_PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>XPC!</string>
  <key>CFBundleShortVersionString</key>
  <string>0.5.7</string>
  <key>CFBundleSupportedPlatforms</key>
  <array><string>MacOSX</string></array>
  <key>CFBundleVersion</key>
  <string>39</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key>
    <string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null
plutil -lint "$WIDGET_INFO_PLIST" >/dev/null
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$SIGNING_BUNDLE"
/usr/bin/xattr -cr "$SIGNING_BUNDLE"
if [[ -n "$SIGN_IDENTITY" ]] && /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
  codesign --force --options runtime --timestamp=none --entitlements "$WIDGET_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$SIGNING_WIDGET_BUNDLE" >/dev/null
  codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$SIGNING_BUNDLE" >/dev/null
else
  echo "warning: signing certificate not found; using a fixed-requirement ad-hoc signature" >&2
  codesign --force --entitlements "$WIDGET_ENTITLEMENTS" --sign - -r="$WIDGET_ADHOC_REQUIREMENT" "$SIGNING_WIDGET_BUNDLE" >/dev/null
  codesign --force --sign - -r="$ADHOC_REQUIREMENT" "$SIGNING_BUNDLE" >/dev/null
fi
/usr/bin/codesign --verify --deep --strict "$SIGNING_BUNDLE"

# Keep a signed distribution copy even when the project lives in a file-provider folder.
/bin/rm -rf "$APP_BUNDLE"
/usr/bin/ditto --norsrc "$SIGNING_BUNDLE" "$APP_BUNDLE"

# Run from /Applications so iCloud does not mutate the live bundle metadata.
/bin/rm -rf "$INSTALLED_APP_BUNDLE"
/usr/bin/ditto --norsrc "$SIGNING_BUNDLE" "$INSTALLED_APP_BUNDLE"
/usr/bin/xattr -cr "$INSTALLED_APP_BUNDLE"
if [[ -n "$SIGN_IDENTITY" ]] && /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
  codesign --force --options runtime --timestamp=none --entitlements "$WIDGET_ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$INSTALLED_WIDGET_BUNDLE" >/dev/null
  codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$INSTALLED_APP_BUNDLE" >/dev/null
else
  codesign --force --entitlements "$WIDGET_ENTITLEMENTS" --sign - -r="$WIDGET_ADHOC_REQUIREMENT" "$INSTALLED_WIDGET_BUNDLE" >/dev/null
  codesign --force --sign - -r="$ADHOC_REQUIREMENT" "$INSTALLED_APP_BUNDLE" >/dev/null
fi
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE"
/usr/bin/pluginkit -a "$INSTALLED_WIDGET_BUNDLE" >/dev/null 2>&1 || true

open_app() {
  /usr/bin/open "$INSTALLED_APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in 1 2 3 4 5; do
      if /usr/bin/pgrep -x "$PROCESS_NAME" >/dev/null; then
        /usr/bin/codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE"
        exit 0
      fi
      sleep 1
    done
    echo "$DISPLAY_NAME did not start" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
