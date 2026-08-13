# AI 工作岛

一个常驻 macOS 桌面的 AI 工作入口：继续 Codex 任务、新建会话，并集中查看本地自动化状态。Touch Bar 是可选的辅助入口，没有 Touch Bar 也可使用桌面面板和悬浮胶囊。

![AI 工作岛胶囊与桌面面板演示](docs/media/ai-work-island-demo.gif)

## 核心能力

- **任务中枢**：统一展示 Codex 任务、未读结果和本地自动化，等待确认、异常和失联状态优先。
- **快速对话**：在顶部创建新任务，或在任务卡中继续对应 Codex 会话；支持粘贴图片。
- **悬浮胶囊**：轮播任务状态与 Codex 额度；异常、失联或等待确认时锁定重要状态。
- **录音守护**：`Option-Command-R` 调用语音备忘录；录音和持续静音时给出提示，绝不自动停止或删除录音。
- **会议纪要进度**：展示转写、生成纪要、写入 Obsidian、推送排队以及已转写待生成状态。

## 安装

需要 macOS 13+。普通用户可在 GitHub Releases 下载 `AI-Work-Island.app.zip`，解压后把“AI 工作岛”拖入“应用程序”并打开。首次启动若被 macOS 拦截，请在“系统设置 → 隐私与安全性”中选择“仍要打开”；录音守护还会请求麦克风和辅助功能权限。

从源码安装需要 Xcode Command Line Tools：

```bash
git clone https://github.com/Neo-niu/ai-work-island.git
cd ai-work-island
./script/build_and_run.sh --verify
```

构建产物位于 `dist/AI 工作岛.app`，验证流程会同时安装到 `/Applications/AI 工作岛.app`。首次使用录音守护时，macOS 会请求麦克风和辅助功能权限。

## 自动化接入

每个任务原子写入一个 JSON 文件到：

```text
~/Library/Application Support/Codex Hermes Touch Bar/automation-status/
```

支持 `running`、`queued`、`waiting`、`failed`、`completed`、`idle` 和 `stale`，也可提供阶段进度、产出路径或打开链接。完整字段见 [状态示例](examples/automation-status.example.json)。

## 隐私边界

- Codex 状态只读本机数据，不额外保存 Token、Cookie 或对话正文。
- 会议纪要卡片只读阶段、会议名、队列数和输出路径，不包含录音、转写稿或纪要正文。
- 录音音量只在内存中判断，不保存、不上传。

## 已知限制

- Touch Bar 常驻依赖 macOS 私有 API，系统升级可能影响兼容性。
- 无 Developer ID 时使用 ad-hoc 签名，重建后 macOS 可能重新请求辅助功能权限。
- 公司额度读取依赖 Edge 中已登录的平台页面；无可用数据时自动隐藏。

## 开发验证

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
dist/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose-automation
```

项目源自 MIT 项目 [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar)，并保留原许可证。
