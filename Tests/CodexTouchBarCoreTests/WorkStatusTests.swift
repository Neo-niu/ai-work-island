@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func onlyFailedAndStaleWorkItemsRequireAttention() {
    #expect(WorkItemStatus.failed.requiresAttention)
    #expect(WorkItemStatus.stale.requiresAttention)
    #expect(!WorkItemStatus.running.requiresAttention)
    #expect(!WorkItemStatus.queued.requiresAttention)
    #expect(!WorkItemStatus.waiting.requiresAttention)
    #expect(!WorkItemStatus.completed.requiresAttention)
    #expect(!WorkItemStatus.idle.requiresAttention)
}

@Test func queuedWorkIsActiveButDoesNotRequireTheUser() {
    #expect(WorkItemStatus.queued.isActiveWork)
    #expect(WorkItemStatus.running.isActiveWork)
    #expect(!WorkItemStatus.waiting.isActiveWork)
}

@Test func workItemDisplayTextRemovesClipboardMarkdownAndNewlines() {
    let item = WorkItem(
        id: "codex:test",
        source: "Codex",
        title: "## codex-clipboard-123.png\n\n## My request:\n优化桌面组件 UI\n不要换行",
        detail: "正在处理\n桌面组件",
        status: .running,
        updatedAt: Date()
    )

    #expect(item.displayTitle == "优化桌面组件 UI")
    #expect(item.displayDetail == "正在处理 桌面组件")
}

@Test func codexThreadsBecomeUnifiedWorkItems() {
    let date = Date(timeIntervalSince1970: 100)
    let active = ActiveThread(
        id: "active",
        title: "正在分析",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: date,
        updatedAt: date,
        isActive: true
    )
    let unread = ActiveThread(
        id: "unread",
        title: "报告已完成",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: date,
        updatedAt: date,
        isActive: false,
        isUnread: true
    )
    let group = ProjectGroup(
        id: "project",
        name: "项目",
        threads: [active, unread],
        isUnnamed: false
    )

    let items = WorkStatusHub.codexItems(from: [group])

    #expect(items.map(\.status) == [.running, .waiting])
    #expect(items.map(\.id) == ["codex:active", "codex:unread"])
}

@Test func automationScannerExpiresAStaleRunningTask() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let json = """
    {
      "id": "daily-merge",
      "source": "数据合并",
      "title": "下载并合并日报",
      "status": "running",
      "updatedAt": "1970-01-01T00:00:10Z",
      "staleAfterSeconds": 30,
      "outputPath": "/tmp/result.xlsx",
      "phase": "下载与合并",
      "phaseIndex": 1,
      "phaseCount": 5
    }
    """
    try Data(json.utf8).write(to: directory.appendingPathComponent("daily-merge.json"))
    let scanner = AutomationStatusScanner(
        statusDirectory: directory,
        now: { Date(timeIntervalSince1970: 100) }
    )

    let result = scanner.scan()

    #expect(result.issues.isEmpty)
    #expect(result.items.count == 1)
    #expect(result.items.first?.status == .stale)
    #expect(result.items.first?.outputPath == "/tmp/result.xlsx")
    #expect(result.items.first?.phase == "下载与合并")
    #expect(result.items.first?.phaseIndex == 1)
    #expect(result.items.first?.phaseCount == 5)
}

@Test func automationScannerReportsInvalidFilesWithoutDroppingValidTasks() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("{}".utf8).write(to: directory.appendingPathComponent("broken.json"))
    let valid = """
    {"id":"ok","title":"正常任务","status":"completed","updatedAt":"1970-01-01T00:01:00Z"}
    """
    try Data(valid.utf8).write(to: directory.appendingPathComponent("valid.json"))

    let result = AutomationStatusScanner(statusDirectory: directory).scan()

    #expect(result.items.count == 1)
    #expect(result.issues.count == 1)
    #expect(result.issues.first?.hasPrefix("broken.json：") == true)
}

@Test func statusHubPutsAttentionBeforeRunningAndCompleted() {
    let date = Date(timeIntervalSince1970: 1)
    let items = [
        WorkItem(id: "done", source: "A", title: "完成", status: .completed, updatedAt: date),
        WorkItem(id: "run", source: "A", title: "运行", status: .running, updatedAt: date),
        WorkItem(id: "wait", source: "A", title: "等待", status: .waiting, updatedAt: date),
    ]

    #expect(WorkStatusHub.merge(codex: [], automation: items).map(\.id) == ["wait", "run", "done"])
}

@Test func statusHubKeepsRunningOrderStableWhenOnlyUpdateTimesChange() {
    let first = WorkItem(
        id: "codex:a",
        source: "Codex",
        title: "A",
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let second = WorkItem(
        id: "codex:b",
        source: "Codex",
        title: "B",
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(WorkStatusHub.merge(codex: [second, first], automation: []).map(\.id) == [
        "codex:a",
        "codex:b",
    ])
}
