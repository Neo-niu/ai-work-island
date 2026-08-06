# AI 接手说明

## 目的

将 Touch Bar 做成以展示为主的 Codex 与 Hermes 状态仪表盘，减少切窗口检查和误触。

## 背景

项目基于 `MarlonJD/codex_touchbar`。用户本机为 M2 Touch Bar MacBook Pro，已安装 Codex/ChatGPT、Hermes Desktop 与 Hermes CLI。

## 当前实现

- Swift 6 + AppKit。
- `RolloutScanner` 读取 Codex 本地状态。
- `HermesStatusScanner` 只读 `gateway_state.json` 和 `kanban.db`。
- `CompanyQuotaScanner` 每 60 秒通过 Edge 页面内同源请求读取 `/api/v1/users/self`，不提取 Cookie。
- `TouchBarController` 默认只展示 Codex 项目/任务汇总、周 Token 使用、公司额度、Hermes 聚合状态和动画宠物。
- 主界面唯一业务交互是五档推理程度滑块；项目跳转、项目展开和速度选择已从 Touch Bar 主界面移除。
- 宠物改为原创机械光核 PNG，构建脚本将 `Resources/mechanical-touchbar-pet-96.png` 复制进 App；动画由 Core Animation 实现，不依赖网络。
- 两个额度各使用一条横向进度条；推理滑块连续更新视觉档位，300ms 防抖后才发送设置。
- Codex 状态每次轮询都会重算，最近 5 秒有 rollout 写入时显示“思考中”，避免时间状态被数据相等判断挡住。
- 菜单栏设置、状态提示和用户可见错误统一使用中文；诊断命令仍保留英文键名，方便脚本解析。
- 拖动推理程度滑块只检查辅助功能权限，不主动触发系统授权弹窗；只有菜单“启用推理程度控制…”会请求系统授权。
- 无开发者证书时使用固定 Bundle ID 的 ad-hoc designated requirement，避免默认 `cdhash` requirement 随每次构建变化；首次切换后仍需重新添加一次辅助功能权限。
- App 默认仅在 Codex 或 Hermes 前台时展开；菜单可切换“始终显示（所有应用）”，状态持久化在 `touchBarAlwaysShow`。
- 构建目录默认放 `/tmp`，避免 iCloud 路径中的 SwiftPM 锁竞争。
- 构建产物保留在 `dist`，实际运行副本安装到 `/Applications`，避免 iCloud 改写 Bundle 元数据。

## 未解决

- 是否需要可配置宠物形象；当前固定为轻量动画猫。
- Token 当前展示 Codex 周额度百分比，不是逐线程精确 Token 数。
- 公司额度目前依赖 Edge 保留平台标签页；可评估平台官方机器凭证或本地安全缓存。
- 等待用户输入与普通 blocked 的进一步区分。
- 正式 Developer ID 签名和 notarization。
- 私有 Touch Bar API 的系统升级兼容性。

## 验证命令

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
./script/build_and_run.sh --verify
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-hermes
```
