#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPIUM_PORT="${APPIUM_PORT:-4724}"
APPIUM_LOG="${TMPDIR:-/tmp}/ai-work-island-appium.log"
APPIUM_URL="http://127.0.0.1:${APPIUM_PORT}/wd/hub"

command -v appium >/dev/null
test -d /Applications/Xcode.app

appium --address 127.0.0.1 --port "$APPIUM_PORT" --base-path /wd/hub >"$APPIUM_LOG" 2>&1 &
APPIUM_PID=$!
trap '/bin/kill "$APPIUM_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
  if /usr/bin/curl --silent --fail "$APPIUM_URL/status" >/dev/null; then
    APPIUM_URL="$APPIUM_URL" /usr/bin/env node "$PROJECT_DIR/Tests/E2E/appium_work_island_smoke.mjs"
    exit 0
  fi
  /bin/sleep 1
done

echo "Appium did not become ready. Log: $APPIUM_LOG" >&2
exit 1
