# AI 接手说明

## 目的

将 Codex 与本地自动化程序汇总为一个状态中枢，并通过桌面面板、macOS 原生小组件和 Touch Bar 三个出口减少切窗口检查。

## 背景

项目基于 `MarlonJD/codex_touchbar`。用户本机为 M2 Touch Bar MacBook Pro，已安装 Codex/ChatGPT、Hermes Desktop 与 Hermes CLI。

## 当前实现

- Swift 6 + AppKit。
- `WorkStatusHub` 将 Codex 线程与自动化任务统一为 `WorkItem`；桌面面板和 Touch Bar 继续各自按信息密度展示。
- `DesktopStatusPanelController` 提供默认可见、跨桌面空间、可移动的桌面小组件；默认位于普通窗口后方并隐藏标题栏控件，可从菜单切换为始终置顶浮窗。顶部显示 Codex/公司剩余额度，最多展示 7 项任务，等待确认、异常和失联优先。
- `等待你` 分组固定排在所有分组之前、始终展开且不能折叠；其中的任务逐条显示并可占满 7 个可见位置，不与运行中或最近完成任务合并。
- 桌面面板通过 `DesktopPanelContentSignature` 忽略仅刷新时间或任务 `updatedAt` 变化的轮询；额度使用独立摘要视图原位更新，不重建任务行。标题、详情、状态、阶段、按钮目标或分组确实变化时才刷新任务内容。
- `CodexStatusWidget` 是 WidgetKit 原生扩展，支持中号和大号；主应用将脱敏后的 `WorkItem` 快照写入扩展沙盒，并触发 timeline 刷新。SwiftPM 扩展入口通过一次性 bootstrap 进入 `NSExtensionMain`，避免 descriptor 查询提前退出。
- `AutomationStatusScanner` 只读 `~/Library/Application Support/Codex Hermes Touch Bar/automation-status/*.json`；运行状态默认 30 分钟未更新转为失联，可由 `staleAfterSeconds` 覆盖或设 0 关闭。
- 菜单可显示/隐藏桌面面板、打开自动化状态目录；点击 Codex 项打开对应会话，点击自动化项打开 `openURL` 或 `outputPath`。
- `RolloutScanner` 读取 Codex 本地状态。
- `HermesStatusScanner` 仅供 `--diagnose-hermes` 手动诊断，常驻刷新不再读取 Hermes 状态。
- `CompanyQuotaScanner` 每 60 秒通过 Edge 页面内同源请求读取 `/api/v1/users/self`，不提取 Cookie。
- `TouchBarController` 只展示 Codex 任务状态、Codex 剩余额度和公司额度，不提供推理程度控制。Codex 胶囊读取 rollout 的 5 小时与周窗口，数据源只提供其中一项时单项显示；公司胶囊显示剩余美元金额，圆环仍表示剩余比例。
- 两个额度组件展示剩余百分比；50% 以下橙色、20% 以下红色。
- 视觉层使用 `NSVisualEffectView` 的系统 HUD 材质、连续圆角与动态系统色；正常态用系统强调色，颜色只承担待读和低额度等状态提示，不模拟自绘“玻璃”特效。
- 主 Touch Bar 依次展示任务、Codex 额度和公司额度；额度胶囊在圆环右侧同时展示额度名称与剩余百分比。
- Codex 状态每次轮询都会重算；零任务时显示“Codex 空闲”，否则只显示非零的处理中/待读数量。处理中按 `isActive` 会话计数，待读按 `isUnread` 会话计数。
- `RolloutScanner` 对缺少 `task_complete` 的异常日志增加 30 分钟活跃失效时间，避免历史 `task_started` 永久占用处理中计数。
- 菜单栏设置、状态提示和用户可见错误统一使用中文；诊断命令仍保留英文键名，方便脚本解析。
- 无开发者证书时使用固定 Bundle ID 的 ad-hoc designated requirement，避免默认 `cdhash` requirement 随每次构建变化；首次切换后仍需重新添加一次辅助功能权限。
- 公司额度扫描通过后台 `reload` 唤醒 Edge 休眠标签，不改变 `active tab index`；读取失败时保留上次成功缓存，避免用户浏览时闪切到额度页。
- App 默认仅在 Codex 前台时展开；菜单可切换“始终显示（所有应用）”，状态持久化在 `touchBarAlwaysShow`。
- 菜单提供“重启应用”：先启动延迟 0.5 秒的本地重开任务，再退出当前进程，避免单实例保护拦截新实例。
- Touch Bar 被关闭按钮收起后，再次打开 `/Applications/Codex Hermes Touch Bar.app` 会通知既有后台进程强制恢复仪表盘，不再被单实例保护静默吞掉。
- “处理中”和“待读”是两个独立点击目标；点击后按各自列表循环，通过 Codex 主窗口的“搜索聊天”命令按精确标题打开会话。不要恢复外部 `codex://threads/<id>` 路径：深链会广播到隐藏的 avatar overlay，产生错误的“会话不存在”提示。
- App 图标母版位于 `Resources/AppIcon-master.png`，构建使用 `Resources/AppIcon.icns`；视觉采用深色圆角设备、横向 Touch Bar 光带与状态脉冲，不包含 Apple 商标。
- 构建目录默认放 `/tmp`，避免 iCloud 路径中的 SwiftPM 锁竞争。
- 构建产物保留在 `dist`，实际运行副本安装到 `/Applications`，避免 iCloud 改写 Bundle 元数据。
- 签名先在系统临时目录完成，再复制回 `dist` 和 `/Applications`；否则文件提供器会立即给 app 根目录补写扩展属性，导致 `codesign` 报 resource fork/Finder information 错误。

## 最近回归

- 2026-08-11：README 面向中文用户统一标题和功能说明，保留命令、路径、协议字段及必要技术专名原文。
- 2026-08-11：0.5.7 build 39 取消 Touch Bar 推理程度滑块及其菜单入口、待应用状态和后台写入链路；主界面只保留任务状态、Codex 额度和公司额度。87 项 Swift 测试、`git diff --check`、严格签名、安装版本和进程状态通过。
- 2026-08-11：0.5.6 build 38 将无归属项目的分组名称统一为中文“任务”。已安装窗口实机回读两条运行任务均显示“正在处理 · 任务 · 执行中”；87 项 Swift 测试、`git diff --check`、严格签名、安装版本和进程状态通过。
- 2026-08-11：0.5.5 build 37 使用 Codex 桌面端本机 IPC 设置目标会话的推理程度，移除无限等待的辅助功能重试主链路。实机在当前任务执行中完成 `low → medium → low`，每次 IPC 均返回成功且 `state_5.sqlite` 同步回读；当前会话最终为 `low`，历史待应用状态已清除。87 项 Swift 测试、`git diff --check`、严格签名、安装版本和进程状态通过。
- 2026-08-11：0.5.4 build 36 将推理选择绑定到目标任务并持久保存。任务执行中显示“低·待”等明确状态；任务结束或应用重启后继续自动应用，目标任务数据库回读一致后才清除待应用状态。当前用户选择已登记为本任务 `low`，等待本轮完成后应用。85 项 Swift 测试与 `git diff --check` 通过。
- 2026-08-11：0.5.3 build 35 将 `等待你` 分组改为固定置顶、始终展开、不可折叠，等待任务逐项显示并优先占用全部 7 个可见位置。推理滑块改为优先直接操作 Codex 推理菜单并支持中文标签；实测旧快捷键在当前 Codex 任务执行中会返回假成功但数据库仍为 `medium`，新实现此时保留待确认选择并在任务结束后自动重试，数据库回读一致才确认。85 项 Swift 测试、`git diff --check`、严格签名、安装版本和进程状态通过。实机临时注入 waiting 任务后回读到置顶的禁用折叠标题与独立任务行；测试文件已删除，状态目录仅剩真实 `mario-daily.json`。当前任务执行中诊断诚实返回“未找到推理程度控件”，数据库保持 `medium`，未误改档位。
- 2026-08-11：0.5.2 build 34 在桌面状态窗口增加 Codex 与公司额度摘要；Codex 自动显示服务端实际提供的 5 小时/周窗口，公司额度显示剩余美元和百分比。修复每秒轮询删除并重建全部任务行及同级运行任务按日志时间反复换位导致的闪烁，改为可见内容签名去重、活动任务稳定排序、额度原位更新；页脚使用任务真实更新时间，不再每秒跳动。84 项 Swift 测试、`git diff --check`、严格签名、安装版本和进程状态通过。实机窗口回读到 `Codex 额度 周 94%` 与 `公司额度 暂不可用`，连续 5 帧跨越 4 次轮询时任务顺序、文字和页脚完全一致，无列表淡出。
- 2026-08-11：0.5.1 build 33 增加完整剩余额度显示。Codex 胶囊同时支持 5 小时和周窗口，以两者较低值驱动警示圆环；公司胶囊直接显示剩余美元金额。安装后诊断回读为周额度剩余 94%，当前数据源未提供 5 小时窗口；公司额度因 Edge 未保留已登录平台标签页而不可用。82 项 Swift 测试、`git diff --check`、严格签名、安装版本和进程状态均通过，桌面状态面板实机回读正常。
- 2026-08-10：0.5.0 build 32 完成桌面看板五项增强：顶部状态改为会随工作态切色和弹性更新的胶囊；任务完成及异常恢复分别使用绿色、蓝色掠光；悬浮任务卡显示“打开任务 / 打开产出 / 详情”快捷操作；自动化协议新增 `phase`、`phaseIndex`、`phaseCount` 并渲染分段进度轨道；任务按“正在执行 / 等待查询 / 需要处理 / 最近完成”自动分组和折叠，首次展开最重要的一组。结构动画保留顶边锚定并遵守系统“减少动态效果”。实机回读状态胶囊、分组、悬浮按钮与 4/5 阶段轨道，折叠时窗口由 280pt 平滑收至 218pt；临时状态文件已删除。81 项 Swift 测试、`git diff --check`、严格签名和安装版本 32 均通过。
- 2026-08-10：0.5.0 build 31 为桌面任务看板加入结构变化动效：仅在可见任务 ID/顺序变化时触发，先用 0.10 秒淡出旧列表，再以 0.34 秒窗口顶边锚定缩放、淡入和纵向弹簧归位呈现新列表；连续刷新在动画结束后合并处理，避免每秒状态轮询打断动画。系统开启“减少动态效果”时完全跳过大幅动画，直接更新布局。实机注入临时任务回测，窗口增长高度连续采样为 360→366→374→387→394→405→411→418→422，缩短也连续回落至 298；临时状态文件已清理。81 项 Swift 测试通过。
- 2026-08-10：0.5.0 build 30 新增 `queued/等待查询`，用于系统排队或等待外部查询；`waiting/等待你` 仅表示确实需要人工处理。排队状态按活动任务频率刷新，但不计入“待处理”。Mario 权限问题处理后的当前状态已改为 `queued`。
- 2026-08-10：WidgetKit 原生“AI 工作状态”中号/大号小组件已嵌入 0.5.0 build 29。刷新策略为面板可见 1 秒、后台运行中 3 秒、后台空闲 30 秒；状态、步骤或产出变化才申请重载，Timeline 按运行 5 分钟、待处理 10 分钟、空闲 30 分钟自适应。运行快照超过 2 分钟显示“数据延迟”、超过 10 分钟显示“状态未更新”，读取失败不误报为空闲。桌面面板改为中性自适应玻璃背景和低对比卡片；`WorkItem.displayTitle/displayDetail` 清理附件名、Markdown 标题和换行，所有标题/步骤严格单行截断，避免溢出和窗口变宽。异常或失联任务单击后先显示问题详情，不再自动打开文件夹；弹窗默认操作为“关闭”，有链接或产出时提供次级“打开详情/打开产出”。Codex 任务标题优先读取 `~/.codex/session_index.jsonl` 的最新 `thread_name`，覆盖 `state_5.sqlite` 中可能滞后的初始提问标题，使看板和会话标题同步。任务点击通过 Codex 原生深链 `codex://threads/{thread-id}` 按稳定 ID 跳转，不再依赖标题匹配或辅助功能树。每次冷启动均默认展示桌面任务看板；手动关闭只影响当前运行周期。任务点击曾通过私有搜索快捷键粘贴标题并回车；搜索未打开时会把标题发进当前会话，build 25 已彻底移除该输入链路及搜索快捷键。实际窗口截图已回读验证背景、卡片和文字层级；曾尝试移除整个标题栏以消除灰色窗口按钮，但会使 AppKit 重建 contentView、主体消失，已回退并保留稳定布局。小组件、桌面面板、菜单栏及全局快捷键 `Option-Command-R` 调用同一录音流程。build 16/17 曾因 `NSWorkspace` completion 违反 `@MainActor` 导致 `SIGTRAP`，build 18 起已修复。扩展已启用，80 项 Swift 测试通过。禁止自动展开系统组件图库。
- 2026-08-10：修复桌面面板被长标题/详情撑宽；宽度固定为 372pt，仅高度随可见任务数变化，标题和详情均单行截断，浮窗也取消缩放按钮。新增宽度回归测试，74 项 Swift 测试通过；0.3.0 build 12 已安装。实机注入超长标题后窗口仍为 372pt，截图确认省略号正确，临时任务已删除。
- 2026-08-10：桌面面板增加小组件模式，默认位于与 macOS 原生桌面组件相同的窗口层级、低于普通应用窗口；交通灯按钮已隐藏，圆角、移动和点击能力保留。实机窗口截图和 CoreGraphics 层级均已回读。
- 2026-08-10：首个真实自动化“下载数据并合并”已接入；桌面小组件回读到 `Mario 数据自动化 / 下载数据并合并 / 空闲`，当前真实文案为等待下次 09:00 运行。
- 2026-08-10：新增统一状态中枢、桌面状态面板和自动化 JSON 协议；73 项 Swift 测试通过。0.3.0（build 10）已安装到 `/Applications` 并以新进程运行；实机回读确认 Codex 与临时自动化任务可同时显示，临时状态文件已移除，自动化诊断回读为 0 项且无异常。
- 2026-08-07：完全访问会话实机回归 `low → xhigh → low` 均成功，数据库逐次回读一致，`approval_mode=never`、`sandbox_policy={"type":"disabled"}` 全程未变化；根因是快捷键队列丢步，不是权限限制。
- 2026-08-07：推理滑块改为从当前会话数据库状态回读，68 项测试通过；实机写入回归被 `CodexRestartRequired` 正确阻止，未改动当前会话的 `low`，需用户在本轮完成后重启一次 Codex 再验证写入。
- 2026-08-07：从菜单实际触发“重启应用”，已验证旧进程退出且 `/Applications` 安装副本以新 PID 重新启动。
- 2026-08-07：67 项 Swift 测试通过；Info.plist、快捷键 JSON、安装包严格签名、单实例重开、Codex/Hermes/公司额度/登录项诊断均通过。
- “搜索聊天”实测可切换后返回当前会话；本轮未出现来自 Codex UI 的 `Conversation state not found`，日志中的同文案仅来自回归命令文本本身。
- 辅助功能树可读取；设置 Electron 增强模式返回 `-25205`，当前搜索跳转不依赖该设置，暂作为系统兼容性告警保留。

## 未解决

- Codex 额度展示服务端窗口的剩余百分比，不是逐线程精确 Token 数；若账号只返回周窗口，5 小时额度不显示。
- 公司额度目前依赖 Edge 保留平台标签页；可评估平台官方机器凭证或本地安全缓存。
- 后续自动化接入若要显示真实阶段进度，需在每个阶段更新 `phase`、`phaseIndex`、`phaseCount`；缺失时看板会正常退化为无轨道卡片。
- 正式 Developer ID 签名和 notarization。
- 私有 Touch Bar API 的系统升级兼容性。
- 其他自动化程序仍需逐个接入状态 JSON；首个 Mario“下载数据并合并”已完成接入。
- 原生小组件尚未由用户手动拖到桌面；不要再用 UI 自动化展开图库，交由用户搜索“AI 工作状态”并添加。

## 验证命令

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
./script/build_and_run.sh --verify
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-hermes
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-automation
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-widget
dist/Codex\ Hermes\ Touch\ Bar.app/Contents/MacOS/CodexTouchBar --diagnose-effort low
```
