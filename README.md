# AI 工作岛

用一个悬浮的 macOS AI 工作入口，继续 Codex 任务、新建项目会话，并在桌面面板查看 Codex 与本地自动化状态。

## 当前能力

- Codex：只显示处理中和待读结果；两者均为零时显示“Codex 空闲”。点击“处理中”或“待读”会将 Codex 切到前台，通过主窗口内搜索循环打开对应状态的会话。
- 桌面面板：默认无标题栏控件并停留在普通窗口后方，跨桌面空间显示 Codex 与自动化任务；窗口四边和四角可原生拖动调整，尺寸会记住，收成胶囊后再次展开仍沿用。等待确认、异常和失联任务优先。有效额度以轻量文本显示，公司额度不可用时不占空间。点击任务卡打开任务，悬停操作只保留“产出”和“详情”。
- 浮窗对话：每张 Codex 项目卡片显示最近一轮 AI 结果，并提供独立输入框；在哪张卡片输入，就按该卡片 thread ID 继续对应会话。顶部常驻“新任务”输入框可直接创建会话，默认使用“文稿”目录或用户通过文件夹按钮选定并记住的工作目录。
- 悬浮胶囊：以蓝、橙、红、绿状态点和简短文字显示运行、等待、异常与完成；支持跨空间拖动、悬停展开和自动收起，点击只恢复面板。所有持续动效遵守系统“减少动态效果”。
- 全局录音快捷键：在任何应用中按 `Option-Command-R`，直接调用同一录音入口；使用系统全局快捷键注册，不监听或保存其他按键。
- 录音守护 V1：语音备忘录录音时，悬浮胶囊优先显示红色“录音 N 分”；连续静音 5 分钟后切为橙色“静音 N 分”，提醒可选择“结束并保留”或“继续录音”。不会自动停止或删除录音，实时音量只在内存中判断，不保存或上传音频。
- 自适应刷新：状态面板可见时每 1 秒、后台有运行任务时每 3 秒、后台空闲时每 30 秒采集。
- 桌面刷新：轮询时间或任务内部更新时间变化不会重建任务列表；只有标题、状态、阶段、分组等可见内容变化才更新界面，额度独立原位刷新。
- 等待处理：`等待你` 分组固定置顶并始终展开，不提供折叠入口；组内任务逐项显示，优先占用面板的 7 个可见位置。
- 桌面面板界面：使用与悬浮胶囊一致的深色烟灰玻璃，主背景、任务卡和输入框按明度分层，蓝色只用于运行态和交互反馈；任务标题自动清理附件名、Markdown 标题和换行，固定为标题/步骤两行，避免内容溢出或撑宽窗口。
- 自动化接入：只读本地 JSON 状态文件；运行任务超过自定义失效时间未更新时显示“失联”。
- 图标：使用深色圆角设备、Touch Bar 光带与状态脉冲组成的 macOS 风格图标，不使用 Apple 商标。
- 额度：Codex 额度胶囊同时展示数据源当前提供的 5 小时与周剩余比例；公司额度显示剩余美元金额并用圆环表示剩余比例。50% 以下转橙，20% 以下转红。
- 公司模型平台：后台刷新 Edge 已登录额度标签页后读取本月额度，不切换当前浏览标签；失败时保留上次成功结果。
- 布局优先级：任务状态在前，Codex 与公司额度圆环在后。
- 触控栏仅展示任务状态、Codex 额度和公司额度，不提供推理程度控制。
- 视觉遵循当前 macOS 原生方向：系统 HUD 材质、连续圆角、动态系统色和克制的层级；正常状态使用系统强调色，仅低额度和待读提醒使用警示色。
- Codex 状态：30 分钟无日志活动且缺少结束事件的异常会话不计入处理中。
- 默认仅在 Codex 位于前台时展开，也可在菜单中开启“始终显示（所有应用）”。
- 所有状态均只读本机文件，不读取提示词正文，不需要 Token。

## 安装与运行

需要 macOS 13+ 与 Xcode Command Line Tools；Touch Bar 仅作为可选状态入口。

```bash
./script/build_and_run.sh --verify
```

生成的应用：

```text
dist/AI 工作岛.app
```

验证运行时会同时安装到 `/Applications/AI 工作岛.app`。源码仍保存在 iCloud，应用从本机“应用程序”目录运行，避免 iCloud 修改签名元数据。

诊断数据源：

```bash
dist/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose
dist/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose-hermes
dist/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose-company-quota
dist/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose-automation
```

## 数据来源

- Codex：`~/.codex/state_5.sqlite`、近期 rollout JSONL、未读线程状态。
- 公司模型平台：Edge 中 `model.zhenguanyu.com` 的现有登录态；不读取或保存 Cookie。
- 自动化程序：`~/Library/Application Support/Codex Hermes Touch Bar/automation-status/*.json`。该目录作为兼容性技术路径保留，不影响应用显示名。

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
- 录音守护需要“麦克风”和“辅助功能”权限：前者只用于实时音量判断，后者只用于读取语音备忘录录音状态及执行用户明确选择的“结束并保留”。

## 验证

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
```

项目源自 MIT 项目 [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar)，并保留原许可证。
