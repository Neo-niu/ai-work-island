# AI 接手说明

## 目的

将 Touch Bar 做成 Codex 与 Hermes 的状态、提醒和跳转入口，减少反复切窗口检查。

## 背景

项目基于 `MarlonJD/codex_touchbar`。用户本机为 M2 Touch Bar MacBook Pro，已安装 Codex/ChatGPT、Hermes Desktop 与 Hermes CLI。

## 当前实现

- Swift 6 + AppKit。
- `RolloutScanner` 读取 Codex 本地状态。
- `HermesStatusScanner` 只读 `gateway_state.json` 和 `kanban.db`。
- `TouchBarController` 展示 Codex 项目、额度、Hermes 聚合状态。
- App 仅在 Codex 或 Hermes 前台时展开。
- 构建目录默认放 `/tmp`，避免 iCloud 路径中的 SwiftPM 锁竞争。

## 未解决

- Hermes 具体任务列表与任务级跳转。
- 等待用户输入与普通 blocked 的进一步区分。
- 正式 Developer ID 签名和 notarization。
- 私有 Touch Bar API 的系统升级兼容性。

## 验证命令

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
./script/build_and_run.sh --verify
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-hermes
```
