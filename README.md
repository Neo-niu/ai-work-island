# Codex Hermes Touch Bar

把 MacBook Pro Touch Bar 变成 Codex 与 Hermes 的轻量状态中控台。

## 当前能力

- Codex：显示活动项目、未读结果、周额度；点击项目跳转对应线程。
- Hermes：读取本机 Gateway 与 Kanban 状态，显示运行、阻塞或失败数量；点击打开 Hermes Desktop。
- 公司模型平台：通过 Edge 已登录页面读取本月剩余额度，显示剩余百分比；点击打开额度页面。
- 仅在 Codex 或 Hermes 位于前台时展开 Touch Bar。
- 所有状态均只读本机文件，不读取提示词正文，不需要 Token。

Hermes 状态优先级：`阻塞 > 失败 > 运行 > 在线 > 离线`。

## 安装与运行

需要 macOS 13+、带实体 Touch Bar 的 MacBook Pro，以及 Xcode Command Line Tools。

```bash
./script/build_and_run.sh --verify
```

生成的 App：

```text
dist/Codex Hermes Touch Bar.app
```

验证运行时会同时安装到 `/Applications/Codex Hermes Touch Bar.app`。源码仍保存在 iCloud，App 从本机 Applications 运行，避免 iCloud 修改签名元数据。

诊断数据源：

```bash
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-hermes
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-company-quota
```

## 数据来源

- Codex：`~/.codex/state_5.sqlite`、近期 rollout JSONL、未读线程状态。
- Hermes：`~/.hermes/gateway_state.json`、`~/.hermes/kanban.db`。
- 公司模型平台：Edge 中 `model.zhenguanyu.com` 的现有登录态；不读取或保存 Cookie。

Hermes 查询使用 SQLite 只读模式；没有上述文件时显示离线，不会创建或修改数据。

## 已知限制

- Touch Bar 常驻能力依赖 macOS 私有 API，未来系统版本可能改变。
- Hermes Desktop 暂无公开会话 deep link，因此点击 Hermes 状态先打开 App，尚不能精确跳转任务。
- 当前 Hermes 只展示聚合数量，下一版再加入具体任务横向列表。
- 公司额度读取要求 Edge 已登录且至少保留一个公司模型平台标签页；否则显示“公司 —”。
- 本地构建采用 ad-hoc 签名；重建后 macOS 可能重新要求辅助功能授权。

## 验证

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
```

项目源自 MIT 项目 [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar)，并保留原许可证。
