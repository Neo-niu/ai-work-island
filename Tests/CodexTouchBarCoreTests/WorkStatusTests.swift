@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func codexLiveProgressBecomesCurrentPhaseWithoutInventingAPercentage() {
    let thread = ActiveThread(
        id: "thread-1",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 200),
        liveProgress: CodexLiveProgress(
            activities: ["正在读取文件", "正在运行测试"]
        )
    )
    let group = ProjectGroup(
        id: "project",
        name: "项目",
        threads: [thread],
        isUnnamed: false
    )

    let item = WorkStatusHub.codexItems(from: [group]).first
    #expect(item?.phase == "正在运行测试")
    #expect(item?.recentActivity == "正在读取文件")
    #expect(item?.phaseIndex == nil)
    #expect(item?.phaseCount == nil)
}

@Test func codexCardStatusRemovesRepeatedActivityPrefixes() {
    let summary = CodexCardStatusSummary.running(
        phase: "正在：核对任务状态",
        completedSteps: 2,
        totalSteps: 4,
        recentActivity: "刚刚：读取任务索引"
    )

    #expect(summary.primary == "进度 2/4 · 当前：核对任务状态")
    #expect(summary.secondary == "最新：读取任务索引")
    #expect(!summary.text.contains("正在：正在"))
}

@Test func codexCardStatusDropsDuplicateRecentActivity() {
    let summary = CodexCardStatusSummary.running(
        phase: "运行测试",
        completedSteps: nil,
        totalSteps: nil,
        recentActivity: "正在运行测试"
    )

    #expect(summary.text == "当前：运行测试")
}

@Test func waitingCodexCardStatesTheRequiredUserAction() {
    let summary = CodexCardStatusSummary.waiting(lastAssistantResult: "本地验证通过")

    #expect(summary.primary == "需要你：查看结果并决定下一步")
    #expect(summary.secondary == "结果：本地验证通过")
}

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

@Test func latestCompletedOpenableItemSkipsNonDestinationsAndUsesRecency() {
    let items = [
        WorkItem(
            id: "older",
            source: "A",
            title: "较早完成",
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 100),
            outputPath: "/tmp/older"
        ),
        WorkItem(
            id: "newer",
            source: "A",
            title: "最新完成",
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 200),
            openURL: "https://example.com/result"
        ),
        WorkItem(
            id: "no-destination",
            source: "A",
            title: "没有入口",
            status: .completed,
            updatedAt: Date(timeIntervalSince1970: 300)
        ),
        WorkItem(
            id: "idle",
            source: "A",
            title: "空闲",
            status: .idle,
            updatedAt: Date(timeIntervalSince1970: 400),
            outputPath: "/tmp/idle"
        ),
    ]

    #expect(WorkStatusHub.latestCompletedOpenableItem(from: items)?.id == "newer")
}
