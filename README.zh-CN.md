<div align="center">

# AI 工作岛 for Codex

**让 Codex 在后台工作，只在需要你时回来。**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple&logoColor=white)](#安装免费预览版)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-22C55E)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/Neo-niu/ai-work-island?label=下载&color=2563EB)](https://github.com/Neo-niu/ai-work-island/releases/latest)

[下载安装](https://github.com/Neo-niu/ai-work-island/releases/latest) · [工作方式](#工作方式) · [隐私边界](#默认本地优先) · [English](README.md)

![AI 工作岛在完整桌面中的实际位置，并从状态胶囊展开为 Codex 任务中枢](docs/media/ai-work-island-fullscreen-demo.webp)

[观看 1080p 演示](docs/media/ai-work-island-fullscreen-demo.mp4) · 桌面背景已做隐私模糊处理

</div>

AI 工作岛是 Codex Desktop 的轻量原生 macOS 伴生工具。任务运行时它保持安静；任务完成、异常或等待你的决定时，它再把你叫回来。

它不替代 Codex、编辑器或 Git，只给后台 Codex 任务一个常驻而克制的桌面入口。

## 它解决什么问题

| 原来的方式 | 使用 AI 工作岛 |
| --- | --- |
| 反复切回 Codex 查看进度 | 用小胶囊查看运行数和待读数 |
| 错过已完成、异常或待确认任务 | “等待你”固定优先并持续可见 |
| 找到正确会话后才能继续输入 | 在任务卡继续准确的 Codex thread |
| 每个自动化维护自己的状态页 | 用本地 JSON 协议汇总真实状态 |

## 工作方式

1. **开始任务**：继续在 Codex Desktop 工作，也可从工作岛新建任务。
2. **切走做别的事**：胶囊只显示重要状态，不占据主工作区。
3. **需要你时回来**：完成、异常和待确认任务进入“等待你”。
4. **继续正确会话**：在卡片回复，或把准确 thread 转回 Codex。

没有明确计划时，工作岛只显示最新动态，不根据耗时虚构百分比。

## 核心能力

- Swift/AppKit 原生应用，108 × 38 pt 桌面胶囊。
- 悬停展开、移开回缩，支持贴边和位置记忆。
- “等待你”、异常和失联优先于普通运行状态。
- 每张卡片稳定绑定自己的 Codex thread ID，避免串会话。
- 转移一条会话不会中断其他并发工作岛任务。
- 清爽 / 详细两种信息密度。
- Touch Bar、录音守护、额度和自动化状态均为可选扩展。

## 安装免费预览版

当前公开版本免费、开源，使用 **ad-hoc 签名**，尚未获得 Apple Developer ID 签名和公证。

1. 从 [最新 GitHub Release](https://github.com/Neo-niu/ai-work-island/releases/latest) 下载 `AI-Work-Island.app.zip`。
2. 解压后把“AI 工作岛.app”移动到“应用程序”。
3. 先尝试打开一次。
4. 如果 macOS 拦截，进入“系统设置 → 隐私与安全性”，确认被拦截的是“AI 工作岛”，再选择“仍要打开”。
5. 只有在使用对应功能时，才授予辅助功能或麦克风权限。

需要 macOS 13 或更高版本；Codex 任务集成需要已安装 Codex Desktop。

> [!IMPORTANT]
> 只从本仓库下载。ad-hoc 预览版无法由 macOS 验证具名开发者身份，请在打开前核对 Release 页面和校验和。重建版本可能需要重新授权辅助功能。

### 从源码构建

```bash
git clone https://github.com/Neo-niu/ai-work-island.git
cd ai-work-island
./script/build_and_run.sh --verify
```

## 默认本地优先

| 数据 | 处理方式 |
| --- | --- |
| Codex 状态 | 读取本机索引和 rollout，不另建对话档案 |
| 对话内容 | 只展示任务卡所需的最近动态与回复摘要 |
| Token / Cookie | 不持久化 |
| 粘贴图片 | 仅暂存于系统临时目录，发送或删除后清理 |
| 录音音量 | 只在内存计算，不保存 PCM 或麦克风历史 |
| 会议自动化 | 只读阶段、标题、队列数和产出位置，不读取正文 |

## 可选扩展

### 本地自动化状态

每个任务原子写入一个 JSON 文件到：

```text
~/Library/Application Support/Codex Hermes Touch Bar/automation-status/
```

```json
{
  "id": "daily-report",
  "title": "生成日报",
  "source": "本地自动化",
  "status": "running",
  "detail": "正在汇总数据",
  "updatedAt": "2026-08-13T06:30:00Z"
}
```

支持 `running`、`queued`、`waiting`、`failed`、`completed`、`idle` 和 `stale`。阶段、产出链接和自定义失效时间见[完整示例](examples/automation-status.example.json)。

### 公司额度、录音与会议纪要

公司额度是面向现有环境的可选适配器；未配置时不影响 Codex 核心能力。录音守护可显示实时音量、持续静音提醒和“结束并保留”。会议纪要自动化通过同一 JSON 协议展示真实阶段，不读取转写稿或纪要正文。

## 已知限制

- 免费预览版使用 ad-hoc 签名，尚未公证。
- Codex Desktop 内部接口变化后可能需要兼容更新。
- Touch Bar 使用 macOS 私有 API，系统升级可能影响兼容性。
- 浮窗只用于状态与快速续接，不承载完整多轮记录。
- 额度只展示本地来源提供的窗口，不是逐线程精确 Token 数。

## 开发验证

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
./script/build_and_run.sh --verify
/Applications/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose-automation
```

项目源自 MIT 项目 [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar)，并保留其许可证声明。
