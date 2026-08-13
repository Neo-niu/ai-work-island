#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
PRODUCT_NAME="CodexTouchBar"
DISPLAY_NAME="AI 工作岛"
PROCESS_NAME="$PRODUCT_NAME"
BUNDLE_ID="dev.kanyun.CodexHermesTouchBar"
MIN_SYSTEM_VERSION="13.0"
DEFAULT_SIGN_IDENTITY=""
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
ADHOC_REQUIREMENT="designated => identifier \"$BUNDLE_ID\""

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SCRATCH_DIR="${CODEX_HERMES_BUILD_DIR:-/tmp/codex-hermes-touch-bar-build}"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_ARCHIVE="$DIST_DIR/$DISPLAY_NAME.app.zip"
INSTALLED_APP_BUNDLE="/Applications/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SIGNING_BUNDLE="$(/usr/bin/mktemp -d)/$DISPLAY_NAME.app"

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

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

swift build --disable-sandbox --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_DIR"
BUILD_BIN_DIR="$(swift build --disable-sandbox --package-path "$ROOT_DIR" --scratch-path "$SCRATCH_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_DIR/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
/usr/bin/ditto "$ROOT_DIR/Resources/AppIcon.icon" "$APP_RESOURCES/AppIcon.icon"
chmod +x "$APP_BINARY"

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
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>0.5.17</string>
  <key>CFBundleVersion</key>
  <string>49</string>
  <key>GitHubReleaseTag</key>
  <string>v2026.08.13</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSMultipleInstancesProhibited</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>仅分析实时音量以提醒长时间静音，不保存或上传音频。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null
/usr/bin/ditto --norsrc "$APP_BUNDLE" "$SIGNING_BUNDLE"
/usr/bin/xattr -cr "$SIGNING_BUNDLE"
if [[ -n "$SIGN_IDENTITY" ]] && /usr/bin/security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "\"$SIGN_IDENTITY\""; then
  codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$SIGNING_BUNDLE" >/dev/null
else
  echo "warning: signing certificate not found; using a fixed-requirement ad-hoc signature" >&2
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
  codesign --force --options runtime --timestamp=none --sign "$SIGN_IDENTITY" "$INSTALLED_APP_BUNDLE" >/dev/null
else
  codesign --force --sign - -r="$ADHOC_REQUIREMENT" "$INSTALLED_APP_BUNDLE" >/dev/null
fi
/usr/bin/codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE"

# Keep the signed dist bundle for delivery without exposing it as a second app
# in Launchpad, Spotlight, or Open With. Only the /Applications copy is active.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -u "$APP_BUNDLE" >/dev/null 2>&1 || true
"$LSREGISTER" -f "$INSTALLED_APP_BUNDLE" >/dev/null 2>&1 || true

# Archive and remove the launchable dist copy so macOS cannot register or run it
# alongside the canonical /Applications installation. Debug mode still keeps it.
if [[ "$MODE" != "--debug" && "$MODE" != "debug" ]]; then
  /bin/rm -f "$APP_ARCHIVE"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ARCHIVE"
  /bin/rm -rf "$APP_BUNDLE"
fi

schedule_independent_relaunch() {
  local old_pid="$1"
  local relaunch_label="dev.kanyun.AIWorkIsland.Relauncher"
  /bin/launchctl remove "$relaunch_label" >/dev/null 2>&1 || true
  /bin/launchctl submit -l "$relaunch_label" -- /bin/sh -c '
    old_pid="$1"
    bundle_path="$2"
    for _ in $(/usr/bin/seq 1 100); do
      if ! /bin/kill -0 "$old_pid" 2>/dev/null; then
        break
      fi
      /bin/sleep 0.1
    done
    /bin/sleep 0.3
    exec /usr/bin/open "$bundle_path"
  ' ai-work-island-relauncher "$old_pid" "$INSTALLED_APP_BUNDLE"
}

relaunch_installed_app() {
  local old_pid
  old_pid="$(/usr/bin/pgrep -x "$PROCESS_NAME" | /usr/bin/head -1 || true)"
  if [[ -z "$old_pid" ]]; then
    /usr/bin/open "$INSTALLED_APP_BUNDLE"
    return
  fi

  schedule_independent_relaunch "$old_pid"
  stop_running_app
}

case "$MODE" in
  run)
    relaunch_installed_app
    ;;
  --debug|debug)
    stop_running_app
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    relaunch_installed_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    relaunch_installed_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    previous_pid="$(/usr/bin/pgrep -x "$PROCESS_NAME" | /usr/bin/head -1 || true)"
    relaunch_installed_app
    for _ in $(/usr/bin/seq 1 30); do
      current_pid="$(/usr/bin/pgrep -x "$PROCESS_NAME" | /usr/bin/head -1 || true)"
      if [[ -n "$current_pid" ]] && [[ "$current_pid" != "$previous_pid" ]]; then
        /usr/bin/codesign --verify --deep --strict "$INSTALLED_APP_BUNDLE"
        exit 0
      fi
      sleep 0.5
    done
    echo "$DISPLAY_NAME did not start" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
