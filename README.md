# Codex Hermes Touch Bar

用同一个 macOS 常驻应用，在桌面和 Touch Bar 查看 Codex 与本地自动化程序状态。

## 当前能力

- Codex：只显示处理中和待读结果；两者均为零时显示“Codex 空闲”。点击“处理中”或“待读”会将 Codex 切到前台，通过主窗口内搜索循环打开对应状态的会话。
- 桌面面板：默认无标题栏控件并停留在普通窗口后方，跨桌面空间显示 Codex、自动化任务及 Codex/公司剩余额度；优先展示等待确认、异常和失联任务，点击可打开 Codex 会话或自动化产出。菜单可切换为始终置顶浮窗。
- macOS 原生小组件：WidgetKit 中号/大号组件，显示 Codex 与自动化的当前步骤、运行时长、待处理数量和最新产出；从系统小组件图库搜索“AI 工作状态”添加，点击可回到状态面板。
- 语音备忘录入口：点击小组件或桌面面板的“录音”，打开苹果“语音备忘录”并以 `Command-N` 立即开始；完成或关闭后，由既有自动会议纪要服务发现并转写。当前服务仅处理 30 秒以上录音。
- 全局录音快捷键：在任何 App 中按 `Option-Command-R`，直接调用同一录音入口；使用系统 Hot Key 注册，不监听或保存其他按键。
- 自适应刷新：状态面板可见时每 1 秒、后台有运行任务时每 3 秒、后台空闲时每 30 秒采集；仅在状态、步骤或产出变化时申请 WidgetKit 重载。运行中 Timeline 为 5 分钟、待处理为 10 分钟、空闲为 30 分钟。
- 刷新保真：小组件显示最后更新时间；运行快照超过 2 分钟显示“数据延迟”、超过 10 分钟显示“状态未更新”，不再将旧数据误报为空闲。右上角 `↻` 可手动请求刷新。
- 桌面刷新：轮询时间或任务内部更新时间变化不会重建任务列表；只有标题、状态、阶段、分组等可见内容变化才更新界面，额度独立原位刷新。
- 等待处理：`等待你` 分组固定置顶并始终展开，不提供折叠入口；组内任务逐项显示，优先占用面板的 7 个可见位置。
- 桌面面板 UI：使用中性自适应玻璃背景和低对比卡片，减少桌面强调色污染；任务标题自动清理附件名、Markdown 标题和换行，固定为标题/步骤两行，避免内容溢出或撑宽窗口。
- 自动化接入：只读本地 JSON 状态文件；运行任务超过自定义失效时间未更新时显示“失联”。
- 图标：使用深色圆角设备、Touch Bar 光带与状态脉冲组成的 macOS 风格图标，不使用 Apple 商标。
- 额度：Codex 额度胶囊同时展示数据源当前提供的 5 小时与周剩余比例；公司额度显示剩余美元金额并用圆环表示剩余比例。50% 以下转橙，20% 以下转红。
- 公司模型平台：后台刷新 Edge 已登录额度标签页后读取本月额度，不切换当前浏览标签；失败时保留上次成功结果。
- 布局优先级：任务状态在前，Codex 与公司额度圆环在后。
- Touch Bar 仅展示任务状态、Codex 额度和公司额度，不提供推理程度控制。
- 视觉遵循当前 macOS 原生方向：系统 HUD 材质、连续圆角、动态系统色和克制的层级；正常状态使用系统强调色，仅低额度和待读提醒使用警示色。
- Codex 状态：30 分钟无日志活动且缺少结束事件的异常会话不计入处理中。
- 默认仅在 Codex 位于前台时展开，也可在菜单中开启“始终显示（所有应用）”。
- 所有状态均只读本机文件，不读取提示词正文，不需要 Token。

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
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-automation
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-widget
```

## 数据来源

- Codex：`~/.codex/state_5.sqlite`、近期 rollout JSONL、未读线程状态。
- 公司模型平台：Edge 中 `model.zhenguanyu.com` 的现有登录态；不读取或保存 Cookie。
- 自动化程序：`~/Library/Application Support/Codex Hermes Touch Bar/automation-status/*.json`。

Hermes 本地状态不再参与常驻刷新；`--diagnose-hermes` 仅保留为手动诊断命令。

## 自动化状态协议

每个任务写一个 JSON 文件，写入时建议先生成临时文件再原子替换。示例见 `examples/automation-status.example.json`。

```json
{
  "id": "daily-data-merge",
  "source": "数据自动化",
  "title": "下载并合并日报",
  "detail": "正在合并 Tableau 导出文件",
  "status": "running",
  "updatedAt": "2026-08-10T10:30:00Z",
  "staleAfterSeconds": 1800,
  "outputPath": "/Users/your-name/Documents/output.xlsx"
}
```

`status` 支持 `running`、`waiting`、`failed`、`completed`、`idle`、`stale`。`updatedAt` 可省略，此时使用文件修改时间；`staleAfterSeconds` 设为 `0` 可关闭运行状态失效判断。也可使用 `openURL` 作为点击跳转目标。

## 已知限制

- Touch Bar 常驻能力依赖 macOS 私有 API，未来系统版本可能改变。
- 公司额度读取要求 Edge 已登录且至少保留一个公司模型平台标签页；否则显示“公司 —”。
- 本地构建采用 ad-hoc 签名；重建后 macOS 可能重新要求辅助功能授权。

## 验证

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
```

项目源自 MIT 项目 [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar)，并保留原许可证。
