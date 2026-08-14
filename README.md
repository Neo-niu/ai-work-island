<div align="center">

# AI Work Island for Codex

**Let Codex work in the background. Come back only when it needs you.**

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple&logoColor=white)](#install-the-free-preview)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift)](Package.swift)
[![License: MIT](https://img.shields.io/badge/License-MIT-22C55E)](LICENSE)
[![Latest Release](https://img.shields.io/github/v/release/Neo-niu/ai-work-island?label=download&color=2563EB)](https://github.com/Neo-niu/ai-work-island/releases/latest)

[Download](https://github.com/Neo-niu/ai-work-island/releases/latest) · [How it works](#how-it-works) · [Privacy](#local-first-by-default) · [中文说明](README.zh-CN.md)

![AI Work Island shown at full-screen scale, expanding from its desktop capsule into the Codex task hub](docs/media/ai-work-island-fullscreen-demo.webp)

[Watch the 1080p demo](docs/media/ai-work-island-fullscreen-demo.mp4) · Background blurred for privacy

</div>

AI Work Island is a lightweight native macOS companion for Codex Desktop. It stays out of the way while tasks run, then surfaces the work that is finished, blocked, or waiting for your decision.

It does **not** replace Codex, your editor, or Git. It gives long-running Codex work one small, persistent place on your desktop.

## Why use it

| Without AI Work Island | With AI Work Island |
| --- | --- |
| Reopen Codex repeatedly to check progress | See running and waiting work from one compact capsule |
| Miss a completed or blocked task | “Needs you” work stays visible and takes priority |
| Search for the right conversation before replying | Continue the exact Codex thread from its task card |
| Guess whether an automation is still alive | Read its real status through a small local JSON protocol |

## How it works

1. **Start in Codex or from the island.** Create a task from the panel, or keep using Codex Desktop normally.
2. **Do something else.** The capsule shows the number of running tasks without taking over your screen.
3. **Return when needed.** Completed, blocked, and approval-waiting work moves to **Needs you**.
4. **Continue the right thread.** Reply from its card or transfer the exact thread back to Codex.

The app only displays step progress when a task has an explicit plan. It never invents a percentage from elapsed time.

## Built for focus

- Native Swift/AppKit app with a 108 × 38 pt desktop capsule.
- Hover to expand; move away to collapse.
- “Needs you”, failures, and stale work outrank routine activity.
- Each task card remains bound to its stable Codex thread ID.
- Multiple Work Island threads can run concurrently; transferring one thread does not interrupt its peers.
- Compact and detailed information modes.
- Resizable, edge-snapping panel that remembers its position.
- Optional Touch Bar, recording guard, usage indicators, and local automation status.

> Touch Bar is optional. The desktop capsule and task panel work without it.

## Install the free preview

The current public build is free, open source, and **ad-hoc signed**. It is not yet Developer ID signed or notarized by Apple.

1. Download `AI-Work-Island.app.zip` from the [latest GitHub Release](https://github.com/Neo-niu/ai-work-island/releases/latest).
2. Unzip it and move **AI 工作岛.app** to **Applications**.
3. Try to open it once.
4. If macOS blocks it, open **System Settings → Privacy & Security**, verify that the blocked app is **AI 工作岛**, then choose **Open Anyway**.
5. Grant Accessibility or Microphone access only if you choose features that require them.

Requires macOS 13 or later and Codex Desktop for Codex task integration.

> [!IMPORTANT]
> Only download builds from this repository. Because the preview is ad-hoc signed, macOS cannot verify a named Developer ID. Check the Release page and checksum before opening it. Rebuilt versions may require Accessibility permission again.

### Build from source

Install Xcode Command Line Tools, then run:

```bash
git clone https://github.com/Neo-niu/ai-work-island.git
cd ai-work-island
./script/build_and_run.sh --verify
```

The build is written to `dist/AI 工作岛.app` and the verification script installs a runnable copy in `/Applications`.

## Local-first by default

| Data | What the app does |
| --- | --- |
| Codex status | Reads local Codex indexes and rollout events; does not create another conversation archive |
| Conversation content | Shows only the latest activity and reply summary needed by the task card |
| Tokens and cookies | Does not persist them |
| Pasted images | Keeps them in a temporary system directory until sent or removed |
| Recording level | Calculates a live volume level in memory; does not save PCM or microphone history |
| Meeting automation | Reads stage, title, queue count, and output location—not the transcript or note body |

## Optional integrations

These are extensions, not prerequisites for the core Codex experience.

### Local automation status

Write one JSON file per task atomically to:

```text
~/Library/Application Support/Codex Hermes Touch Bar/automation-status/
```

Minimal example:

```json
{
  "id": "daily-report",
  "title": "Generate daily report",
  "source": "Local automation",
  "status": "running",
  "detail": "Aggregating source data",
  "updatedAt": "2026-08-13T06:30:00Z"
}
```

Supported states include `running`, `queued`, `waiting`, `failed`, `completed`, `idle`, and `stale`. See the [full example](examples/automation-status.example.json) for phases, output links, and custom stale thresholds.

### Company quota indicator

The existing company-quota adapter is environment-specific and optional. It reads a same-origin response from an already signed-in Microsoft Edge tab and never extracts or stores the browser cookie. If it is not configured, the core Codex task experience still works.

### Recording and meeting automation

The recording guard can display a live level, warn after sustained silence, and let the user stop while keeping the recording. Meeting-note automations can expose their real pipeline stage through the same local JSON protocol.

## Known limitations

- The free preview is ad-hoc signed and not notarized.
- Codex Desktop internals may change; new Codex releases can require compatibility updates.
- Touch Bar support uses private macOS APIs and may change after a system update.
- The floating panel is for status and quick continuation, not full transcript browsing.
- Exact token usage is not available per thread; quota indicators only show windows exposed by the local source.

## Development and verification

```bash
swift test --disable-sandbox --scratch-path /tmp/codex-hermes-touch-bar-tests
./script/build_and_run.sh --verify
/Applications/AI\ 工作岛.app/Contents/MacOS/CodexTouchBar --diagnose-automation
```

Release candidates are checked from the packaged artifact—not only from the source build:

```bash
./script/verify_release_candidate.sh path/to/AI-Work-Island.app.zip
```

## Project status

AI Work Island is an early public preview shaped around a simple question:

> Can a new Codex user install it and see the first real task within five minutes?

Bug reports and first-run feedback are especially useful. Please include the macOS version, Codex version, installation step, expected result, and what appeared instead. Do not attach conversation content, tokens, cookies, or private logs.

## Credits

AI Work Island started from the MIT-licensed [MarlonJD/codex_touchbar](https://github.com/MarlonJD/codex_touchbar) project and retains its license notices.
