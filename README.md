# Codex Hermes Touch Bar

把 MacBook Pro Touch Bar 变成以展示为主的 Codex 与 Hermes 状态仪表盘。

## 当前能力

- Codex：汇总显示项目数、运行任务数和待读结果，不再用 Touch Bar 浏览或点击具体项目。
- Token：Codex 周额度与公司额度各用一条横向进度条展示已用比例。
- Hermes：只读本机 Gateway 与 Kanban 状态，显示运行、阻塞或失败数量。
- 公司模型平台：后台刷新 Edge 已登录额度标签页后读取本月额度，不切换当前浏览标签；失败时保留上次成功结果。
- 推理程度：五档连续反馈滑块，拖动时档位光点和文字即时变化，停止后再应用设置。
- 宠物：左侧常驻 Siri 风格玻璃状态光球；空闲时仅有极慢微光漂移，处理中时显示多层光流、柔光扩散、变色外环与双层呼吸动画，并遵循系统“减少动态效果”设置。
- Codex 状态：只显示“处理中会话数”和“待查看会话数”；30 分钟无日志活动且缺少结束事件的异常会话不计入处理中。
- 默认仅在 Codex 或 Hermes 位于前台时展开，也可在菜单中开启“始终显示（所有应用）”。
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
- 当前 Hermes 只展示聚合数量，不展示具体任务列表。
- 公司额度读取要求 Edge 已登录且至少保留一个公司模型平台标签页；否则显示“公司 —”。
- 推理程度滑块依赖辅助功能权限控制 Codex；失败时不会修改 Codex 设置。
- 本地构建采用 ad-hoc 签名；重建后 macOS 可能重新要求辅助功能授权。

## 验证

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
```

项目源自 MIT 项目 [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar)，并保留原许可证。
