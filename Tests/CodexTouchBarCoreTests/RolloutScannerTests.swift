import CSQLite
@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func readsCurrentThreadReasoningEffortByRecency() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let databaseURL = root.appendingPathComponent("state.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    guard let database else { return }
    defer { sqlite3_close(database) }
    let sql = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY, model TEXT, reasoning_effort TEXT, archived INTEGER NOT NULL,
      recency_at_ms INTEGER, updated_at_ms INTEGER, updated_at INTEGER NOT NULL
    );
    INSERT INTO threads VALUES ('older', 'gpt-old', 'high', 0, 100, 100, 1);
    INSERT INTO threads VALUES ('current', 'gpt-current', 'xhigh', 0, 200, 200, 1);
    """
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: databaseURL,
        globalStateFile: nil
    )
    #expect(await scanner.currentReasoningEffort() == "xhigh")
    #expect(
        await scanner.currentThreadReasoningSetting()
            == CurrentThreadReasoningSetting(
                threadID: "current",
                model: "gpt-current",
                effort: "xhigh"
            )
    )
}

@Test func reportsOnlyRolloutsWhoseLatestTaskEventIsStarted() async throws {
    let sessionsRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: sessionsRoot) }
    try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)

    try rollout(
        id: "active-thread",
        cwd: "/tmp/active",
        events: ["task_started"],
        at: sessionsRoot.appendingPathComponent("active.jsonl")
    )
    try rollout(
        id: "complete-thread",
        cwd: "/tmp/complete",
        events: ["task_started", "task_complete"],
        at: sessionsRoot.appendingPathComponent("complete.jsonl")
    )
    try rollout(
        id: "aborted-thread",
        cwd: "/tmp/aborted",
        events: ["task_started", "turn_aborted"],
        at: sessionsRoot.appendingPathComponent("aborted.jsonl")
    )
    try rollout(
        id: "internal-subagent",
        cwd: "/tmp/active",
        threadSource: "subagent",
        events: ["task_started"],
        at: sessionsRoot.appendingPathComponent("subagent.jsonl")
    )

    let scanner = RolloutScanner(
        sessionsRoot: sessionsRoot,
        stateDatabase: nil,
        globalStateFile: nil,
        recentFileInterval: 60
    )
    let threads = await scanner.scan()

    #expect(threads.map(\.id) == ["active-thread"])
    #expect(threads.first?.cwd.path == "/tmp/active")
}

@Test func ignoresAStaleTaskStartedWithoutACompletionEvent() async throws {
    let sessionsRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: sessionsRoot) }
    try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)

    let staleRollout = sessionsRoot.appendingPathComponent("stale.jsonl")
    try rollout(
        id: "stale-thread",
        cwd: "/tmp/stale",
        events: ["task_started"],
        at: staleRollout
    )
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(-120)],
        ofItemAtPath: staleRollout.path
    )

    let scanner = RolloutScanner(
        sessionsRoot: sessionsRoot,
        stateDatabase: nil,
        globalStateFile: nil,
        recentFileInterval: 300,
        activeStaleInterval: 60
    )

    #expect(await scanner.scan().isEmpty)
}

@Test func reportsVisibleRootWhenItsDelegatedTaskIsActive() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let rootRollout = root.appendingPathComponent("root.jsonl")
    let childRollout = root.appendingPathComponent("child.jsonl")
    try rollout(
        id: "visible-root",
        cwd: "/tmp/visible-project",
        events: ["task_started", "task_complete"],
        at: rootRollout
    )
    try rollout(
        id: "delegated-child",
        cwd: "/tmp/visible-project",
        threadSource: "subagent",
        events: ["task_started"],
        at: childRollout
    )

    let databaseURL = root.appendingPathComponent("state.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    guard let database else {
        return
    }
    defer { sqlite3_close(database) }

    let updatedAt = Int64(Date().addingTimeInterval(-120).timeIntervalSince1970)
    let childUpdatedAt = Int64(Date().addingTimeInterval(-10).timeIntervalSince1970)
    let sql = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      cwd TEXT NOT NULL,
      rollout_path TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      recency_at_ms INTEGER NOT NULL,
      archived INTEGER NOT NULL
    );
    CREATE TABLE thread_spawn_edges (
      parent_thread_id TEXT NOT NULL,
      child_thread_id TEXT NOT NULL
    );
    INSERT INTO threads VALUES (
      'visible-root', 'Visible root', '/tmp/visible-project', '\(rootRollout.path)',
      \(updatedAt), \(updatedAt * 1_000), 0
    );
    INSERT INTO threads VALUES (
      'delegated-child', 'Delegated child', '/tmp/visible-project', '\(childRollout.path)',
      \(childUpdatedAt), \(childUpdatedAt * 1_000), 0
    );
    INSERT INTO thread_spawn_edges VALUES ('visible-root', 'delegated-child');
    """
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: databaseURL,
        globalStateFile: nil,
        recentFileInterval: 60
    )
    let threads = await scanner.scan()

    #expect(threads.map(\.id) == ["visible-root"])
    #expect(threads.first?.cwd.path == "/tmp/visible-project")
    #expect(Int64(threads.first?.updatedAt.timeIntervalSince1970 ?? 0) == updatedAt)
    #expect(Int64(threads.first?.projectRecencyAt.timeIntervalSince1970 ?? 0) == childUpdatedAt)
}

@Test func sessionIndexNameOverridesTheStaleDatabaseTitle() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let rolloutURL = root.appendingPathComponent("root.jsonl")
    try rollout(
        id: "renamed-thread",
        cwd: "/tmp/project",
        events: ["task_started"],
        at: rolloutURL
    )
    let databaseURL = root.appendingPathComponent("state.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    guard let database else { return }
    defer { sqlite3_close(database) }
    let updatedAt = Int64(Date().timeIntervalSince1970)
    let sql = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, cwd TEXT NOT NULL,
      rollout_path TEXT NOT NULL, updated_at INTEGER NOT NULL,
      recency_at_ms INTEGER NOT NULL, archived INTEGER NOT NULL
    );
    CREATE TABLE thread_spawn_edges (
      parent_thread_id TEXT NOT NULL, child_thread_id TEXT NOT NULL
    );
    INSERT INTO threads VALUES (
      'renamed-thread', 'Original prompt', '/tmp/project', '\(rolloutURL.path)',
      \(updatedAt), \(updatedAt * 1_000), 0
    );
    """
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)

    let sessionIndexURL = root.appendingPathComponent("session_index.jsonl")
    try """
    {"id":"renamed-thread","thread_name":"Current conversation title","updated_at":"2026-08-10T03:37:21Z"}

    """.write(to: sessionIndexURL, atomically: true, encoding: .utf8)
    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: databaseURL,
        globalStateFile: nil,
        sessionIndexFile: sessionIndexURL,
        recentFileInterval: 60
    )

    #expect(await scanner.scan().first?.title == "Current conversation title")
}

@Test func doesNotMapAnUnreadDelegatedTaskToItsVisibleRoot() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let rootRollout = root.appendingPathComponent("root.jsonl")
    let childRollout = root.appendingPathComponent("child.jsonl")
    try rollout(
        id: "visible-root",
        cwd: "/tmp/visible-project",
        events: ["task_started", "task_complete"],
        at: rootRollout
    )
    try rollout(
        id: "delegated-child",
        cwd: "/tmp/visible-project",
        threadSource: "subagent",
        events: ["task_started", "task_complete"],
        at: childRollout
    )

    let databaseURL = root.appendingPathComponent("state.sqlite")
    var database: OpaquePointer?
    #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
    guard let database else {
        return
    }
    defer { sqlite3_close(database) }

    let updatedAt = Int64(Date().addingTimeInterval(-10).timeIntervalSince1970)
    let sql = """
    CREATE TABLE threads (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      cwd TEXT NOT NULL,
      rollout_path TEXT NOT NULL,
      updated_at INTEGER NOT NULL,
      recency_at_ms INTEGER NOT NULL,
      archived INTEGER NOT NULL
    );
    CREATE TABLE thread_spawn_edges (
      parent_thread_id TEXT NOT NULL,
      child_thread_id TEXT NOT NULL
    );
    INSERT INTO threads VALUES (
      'visible-root', 'Visible root', '/tmp/visible-project', '\(rootRollout.path)',
      \(updatedAt), \(updatedAt * 1_000), 0
    );
    INSERT INTO threads VALUES (
      'delegated-child', 'Delegated child', '/tmp/visible-project', '\(childRollout.path)',
      \(updatedAt), \(updatedAt * 1_000), 0
    );
    INSERT INTO thread_spawn_edges VALUES ('visible-root', 'delegated-child');
    """
    #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)

    let globalStateFile = root.appendingPathComponent("global-state.json")
    let globalState = """
    {"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{"local":["delegated-child"]}}}
    """
    try globalState.write(to: globalStateFile, atomically: true, encoding: .utf8)

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: databaseURL,
        globalStateFile: globalStateFile,
        recentFileInterval: 60
    )
    let snapshot = await scanner.scanSnapshot()

    #expect(snapshot.threads.isEmpty)
}

@Test func reportsTheLatestWeeklyLimitAcrossOldAndNewRateLimitShapes() async throws {
    let sessionsRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: sessionsRoot) }
    try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)

    let older = """
    {"timestamp":"2026-07-21T01:00:00.000Z","type":"session_meta","payload":{"id":"older","cwd":"/tmp/older","thread_source":"user"}}
    {"timestamp":"2026-07-21T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":25,"window_minutes":300,"resets_at":1784685660},"secondary":{"used_percent":6,"window_minutes":10080,"resets_at":1785286860}}}}
    {"timestamp":"2026-07-21T01:02:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}

    """
    let newer = """
    {"timestamp":"2026-07-22T01:00:00.000Z","type":"session_meta","payload":{"id":"newer","cwd":"/tmp/newer","thread_source":"user"}}
    {"timestamp":"2026-07-22T01:00:30.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":5,"window_minutes":10080,"resets_at":1785373260},"secondary":null}}}
    {"timestamp":"2026-07-22T01:01:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":7,"window_minutes":10080,"resets_at":1785373260},"secondary":null}}}
    {"timestamp":"2026-07-22T01:02:00.000Z","type":"event_msg","payload":{"type":"task_complete"}}

    """
    try older.write(
        to: sessionsRoot.appendingPathComponent("older.jsonl"),
        atomically: true,
        encoding: .utf8
    )
    try newer.write(
        to: sessionsRoot.appendingPathComponent("newer.jsonl"),
        atomically: true,
        encoding: .utf8
    )

    let scanner = RolloutScanner(
        sessionsRoot: sessionsRoot,
        stateDatabase: nil,
        globalStateFile: nil,
        recentFileInterval: 7 * 24 * 60 * 60
    )
    let snapshot = await scanner.scanSnapshot()

    #expect(snapshot.shortTermLimit?.usedPercent == 25)
    #expect(snapshot.shortTermLimit?.remainingPercent == 75)
    #expect(snapshot.weeklyLimit?.usedPercent == 7)
    #expect(snapshot.weeklyLimit?.remainingPercent == 93)
}

@Test func reportsCompletedUnreadTasksAlongsideActiveTasks() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let projectPath = root.appendingPathComponent("project", isDirectory: true).path
    try rollout(
        id: "active-thread",
        cwd: projectPath,
        events: ["task_started"],
        at: root.appendingPathComponent("active.jsonl")
    )
    try rollout(
        id: "unread-completed-thread",
        cwd: projectPath,
        events: ["task_started", "task_complete"],
        at: root.appendingPathComponent("completed.jsonl")
    )

    let globalStateFile = root.appendingPathComponent("global-state.json")
    let globalState = """
    {"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{"local":["active-thread","unread-completed-thread"]}}}
    """
    try globalState.write(to: globalStateFile, atomically: true, encoding: .utf8)

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: nil,
        globalStateFile: globalStateFile,
        recentFileInterval: 60
    )
    let snapshot = await scanner.scanSnapshot()

    #expect(Set(snapshot.threads.map(\.id)) == ["active-thread", "unread-completed-thread"])
    #expect(snapshot.threads.first { $0.id == "active-thread" }?.isActive == true)
    #expect(snapshot.threads.first { $0.id == "active-thread" }?.isUnread == false)
    #expect(snapshot.threads.first { $0.id == "unread-completed-thread" }?.isActive == false)
    #expect(snapshot.threads.first { $0.id == "unread-completed-thread" }?.isUnread == true)
}

@Test func openingACompletedThreadClearsWaitingUntilItHasANewerResult() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let threadID = "opened-thread"
    let rolloutFile = root.appendingPathComponent("completed.jsonl")
    try rollout(
        id: threadID,
        cwd: root.path,
        events: ["task_started", "task_complete"],
        at: rolloutFile
    )
    let globalStateFile = root.appendingPathComponent("global-state.json")
    try "{\"electron-persisted-atom-state\":{\"unread-thread-ids-by-host-v1\":{\"local\":[\"\(threadID)\"]}}}"
        .write(to: globalStateFile, atomically: true, encoding: .utf8)
    let viewedThreadFile = root.appendingPathComponent("viewed.json")
    try ViewedThreadStore.markViewed(
        threadID: threadID,
        at: Date().addingTimeInterval(1),
        file: viewedThreadFile
    )

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: nil,
        globalStateFile: globalStateFile,
        retainedThreadFile: nil,
        viewedThreadFile: viewedThreadFile,
        recentFileInterval: 60
    )
    #expect(await scanner.scan().isEmpty)

    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(2)],
        ofItemAtPath: rolloutFile.path
    )
    #expect(await scanner.scan().map(\.id) == [threadID])
}

@Test func reloadsUnreadIDsWhenGlobalStateContentsChangeWithoutMetadataChange() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let unreadThreadID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    let unrelatedThreadID = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    try rollout(
        id: unreadThreadID,
        cwd: "/tmp/unread-project",
        events: ["task_started", "task_complete"],
        at: root.appendingPathComponent("completed.jsonl")
    )

    let globalStateFile = root.appendingPathComponent("global-state.json")
    func writeUnreadID(_ id: String) throws {
        let globalState = """
        {"electron-persisted-atom-state":{"unread-thread-ids-by-host-v1":{"local":["\(id)"]}}}
        """
        try globalState.write(to: globalStateFile, atomically: true, encoding: .utf8)
    }

    try writeUnreadID(unrelatedThreadID)
    let stableModificationDate = Date(timeIntervalSince1970: 1_700_000_000)
    try FileManager.default.setAttributes(
        [.modificationDate: stableModificationDate],
        ofItemAtPath: globalStateFile.path
    )
    let initialAttributes = try FileManager.default.attributesOfItem(atPath: globalStateFile.path)
    let initialModificationDate = try #require(initialAttributes[.modificationDate] as? Date)
    let initialSize = try #require(initialAttributes[.size] as? NSNumber)

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: nil,
        globalStateFile: globalStateFile,
        recentFileInterval: 60
    )
    #expect(await scanner.scan().isEmpty)

    try writeUnreadID(unreadThreadID)
    try FileManager.default.setAttributes(
        [.modificationDate: initialModificationDate],
        ofItemAtPath: globalStateFile.path
    )
    let changedAttributes = try FileManager.default.attributesOfItem(atPath: globalStateFile.path)
    let changedModificationDate = try #require(changedAttributes[.modificationDate] as? Date)
    #expect(changedAttributes[.size] as? NSNumber == initialSize)
    #expect(abs(changedModificationDate.timeIntervalSince(initialModificationDate)) < 0.001)

    let threads = await scanner.scan()

    #expect(threads.map(\.id) == [unreadThreadID])
    #expect(threads.first?.isUnread == true)
}

@Test func reportsTheSelectedLocalProjectRoots() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    let selectedRoot = root.appendingPathComponent("selected-project", isDirectory: true)
    let globalStateFile = root.appendingPathComponent("global-state.json")
    let globalState = """
    {
      "selected-project":{"type":"local","projectId":"selected-id"},
      "local-projects":{
        "selected-id":{
          "id":"selected-id",
          "name":"selected-project",
          "rootPaths":["\(selectedRoot.path)"]
        }
      },
      "electron-persisted-atom-state":{
        "unread-thread-ids-by-host-v1":{"local":[]}
      }
    }
    """
    try globalState.write(to: globalStateFile, atomically: true, encoding: .utf8)

    let scanner = RolloutScanner(
        sessionsRoot: root,
        stateDatabase: nil,
        globalStateFile: globalStateFile,
        recentFileInterval: 60
    )
    let snapshot = await scanner.scanSnapshot()

    #expect(snapshot.selectedProjectRoots.map(\.path) == [selectedRoot.path])
}

@Test func weeklyLimitRemainingPercentageIsRoundedAndClamped() {
    let now = Date()

    #expect(WeeklyLimitUsage(usedPercent: 5.6, resetsAt: nil, recordedAt: now).remainingPercent == 94)
    #expect(WeeklyLimitUsage(usedPercent: -2, resetsAt: nil, recordedAt: now).remainingPercent == 100)
    #expect(WeeklyLimitUsage(usedPercent: 140, resetsAt: nil, recordedAt: now).remainingPercent == 0)
}

private func rollout(
    id: String,
    cwd: String,
    threadSource: String = "user",
    events: [String],
    at url: URL
) throws {
    var lines = [
        "{\"timestamp\":\"2026-07-21T01:00:00.000Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\",\"cwd\":\"\(cwd)\",\"thread_source\":\"\(threadSource)\"}}",
    ]
    lines.append(contentsOf: events.enumerated().map { index, event in
        "{\"timestamp\":\"2026-07-21T01:00:0\(index + 1).000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(event)\"}}"
    })
    try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
}

@Test func tailReaderProcessesOnlyBytesAppendedAfterTheCursor() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }

    let initial = String(repeating: "{\"type\":\"response_item\"}\n", count: 20_000)
    try initial.write(to: url, atomically: true, encoding: .utf8)
    let initialSize = UInt64(initial.utf8.count)
    let appended = """
    {"type":"response_item"}
    {"timestamp":"2026-07-21T01:00:01.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":6,"window_minutes":10080,"resets_at":1785286860}}}}
    {"timestamp":"2026-07-21T01:00:02.000Z","type":"event_msg","payload":{"type":"task_complete"}}

    """
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(appended.utf8))
    try handle.close()

    let update = try RolloutTailReader.readChanges(at: url, from: initialSize)

    #expect(update.bytesRead == appended.utf8.count)
    #expect(update.processedOffset == initialSize + UInt64(appended.utf8.count))
    #expect(update.latestEvent?.type == "task_complete")
    #expect(update.latestShortTermLimit == nil)
    #expect(update.latestWeeklyLimit?.remainingPercent == 94)
}

@Test func tailReaderReportsFiveHourAndWeeklyRemainingQuota() throws {
    let line = Data("""
    {"timestamp":"2026-07-21T01:00:01.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":31,"window_minutes":300,"resets_at":1784685660},"secondary":{"used_percent":8,"window_minutes":10080,"resets_at":1785286860}}}}
    """.utf8)

    let events = RolloutTailReader.lineEvents(in: line)

    #expect(events.shortTermLimit?.remainingPercent == 69)
    #expect(events.weeklyLimit?.remainingPercent == 92)
}

@Test func tailReaderExtractsOnlyTheLatestFinalAssistantResult() throws {
    let commentary = Data("""
    {"type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"处理中间状态"}}
    """.utf8)
    let final = Data("""
    {"type":"event_msg","payload":{"type":"agent_message","phase":"final_answer","message":" 已完成第一项。\\n 下一步可以继续。 "}}
    """.utf8)

    #expect(RolloutTailReader.assistantResult(in: commentary) == nil)
    #expect(
        RolloutTailReader.assistantResult(in: final)
            == "已完成第一项。 下一步可以继续。"
    )
}

@Test func tailReaderExtractsCommentaryAsLiveActivity() {
    let eventMessage = Data(#"""
    {"type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":" 正在检查任务状态。\n 稍后继续。 "}}
    """#.utf8)
    let responseItem = Data("""
    {"type":"response_item","payload":{"type":"message","role":"assistant","phase":"commentary","content":[{"type":"output_text","text":"正在运行回归测试"}]}}
    """.utf8)

    #expect(RolloutTailReader.activityMessage(in: eventMessage) == "正在检查任务状态。 稍后继续。")
    #expect(RolloutTailReader.activityMessage(in: responseItem) == "正在运行回归测试")
    #expect(RolloutTailReader.assistantResult(in: eventMessage) == nil)
}

@Test func tailReaderUsesExplicitPlanForRealStepProgress() {
    let line = Data(#"""
    {"type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"{\"plan\":[{\"step\":\"检查输入\",\"status\":\"completed\"},{\"step\":\"实现界面\",\"status\":\"in_progress\"},{\"step\":\"完成回归\",\"status\":\"pending\"}]}"}}
    """#.utf8)

    let progress = RolloutTailReader.planProgress(in: line)
    #expect(progress?.completedStepCount == 1)
    #expect(progress?.totalStepCount == 3)
    #expect(progress?.currentActivity == "实现界面")
}

@Test func tailReaderReadsPlanFromCurrentCustomToolEnvelope() {
    let line = Data(#"""
    {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const r = await tools.update_plan({plan:[{step:\"读取项目\",status:\"completed\"},{step:\"验证界面\",status:\"in_progress\"}]}); text(r);"}}
    """#.utf8)

    let progress = RolloutTailReader.planProgress(in: line)
    #expect(progress?.completedStepCount == 1)
    #expect(progress?.totalStepCount == 2)
    #expect(progress?.currentActivity == "验证界面")
}

@Test func tailReaderReadsQuotedKeysFromDesktopExecPlan() {
    let line = Data(#"""
    {"type":"response_item","payload":{"type":"custom_tool_call","name":"exec","input":"const r = await tools.update_plan({plan:[{step:\"读取项目\",\"status\":\"completed\"},{step:\"验证界面\",\"status\":\"in_progress\"}]}); text(r);"}}
    """#.utf8)

    let progress = RolloutTailReader.planProgress(in: line)
    #expect(progress?.completedStepCount == 1)
    #expect(progress?.totalStepCount == 2)
    #expect(progress?.currentActivity == "验证界面")
}

@Test func tailReaderResetsLiveProgressAtANewTaskStart() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try """
    {"type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"旧任务动态"}}
    {"type":"event_msg","payload":{"type":"task_started"}}
    {"type":"event_msg","payload":{"type":"agent_message","phase":"commentary","message":"新任务动态"}}

    """.write(to: url, atomically: true, encoding: .utf8)

    let update = try RolloutTailReader.readChanges(at: url, from: 0)
    #expect(update.resetsLiveProgress)
    #expect(update.liveActivities == ["新任务动态"])
}

@Test func tailReaderRetriesAnIncompleteFinalLine() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }

    let firstHalf = "{\"timestamp\":\"2026-07-21T01:00:02.000Z\",\"type\":\"event_msg\","
    try firstHalf.write(to: url, atomically: true, encoding: .utf8)

    let incomplete = try RolloutTailReader.readChanges(at: url, from: 0)
    #expect(incomplete.processedOffset == 0)
    #expect(incomplete.latestEvent == nil)

    let secondHalf = "\"payload\":{\"type\":\"task_started\"}}\n"
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(secondHalf.utf8))
    try handle.close()

    let complete = try RolloutTailReader.readChanges(at: url, from: incomplete.processedOffset)
    #expect(complete.processedOffset == UInt64(firstHalf.utf8.count + secondHalf.utf8.count))
    #expect(complete.latestEvent?.type == "task_started")
}
