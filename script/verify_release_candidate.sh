#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_SCRATCH="${TMPDIR:-/tmp}/ai-work-island-release-tests"
APP_BUNDLE="/Applications/AI 工作岛.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/CodexTouchBar"

cd "$PROJECT_DIR"

echo "[1/8] Swift 与视觉回归测试"
swift test --disable-sandbox --scratch-path "$TEST_SCRATCH"

echo "[2/8] 补丁格式检查"
git diff --check

echo "[3/8] 构建、安装与进程重启验证"
./script/build_and_run.sh --verify

echo "[4/8] 安装包严格签名"
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

echo "[5/8] 单实例检查"
PROCESS_COUNT="$(/usr/bin/pgrep -f "$APP_EXECUTABLE" | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
test "$PROCESS_COUNT" = "1"

echo "[6/8] 数据源诊断"
"$APP_EXECUTABLE" --diagnose-hermes
"$APP_EXECUTABLE" --diagnose-automation

echo "[7/8] 安装版辅助功能树"
"$APP_EXECUTABLE" --diagnose-accessibility-pid "$(/usr/bin/pgrep -f "$APP_EXECUTABLE")"

echo "[8/8] Appium Mac2 安装版黑盒冒烟"
./script/run_appium_smoke.sh

echo "AI 工作岛发布候选自动闸门通过。仍需按 docs/TESTING.md 完成尚未自动化的验收项。"
