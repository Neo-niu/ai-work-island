import CSQLite
import Foundation

public actor RolloutScanner {
    private struct CachedRollout {
        let modificationDate: Date
        let fileSize: Int
        let processedOffset: UInt64
        let allowsSubagent: Bool
        let record: RolloutRecord?
    }

    private struct RolloutRecord {
        let thread: ActiveThread
        let isActive: Bool
        let shortTermLimit: WeeklyLimitUsage?
        let weeklyLimit: WeeklyLimitUsage?
    }

    private struct LatestRolloutEvents {
        let task: RolloutTaskEvent?
        let shortTermLimit: WeeklyLimitUsage?
        let weeklyLimit: WeeklyLimitUsage?
        let assistantResult: String?
    }

    private struct GlobalStateValues {
        let unreadThreadIDs: Set<String>
        let selectedProjectRoots: [URL]
    }

    private struct IndexedThreadRoot {
        let id: String
        let title: String
        let cwd: URL
        let updatedAt: Date
        let projectRecencyAt: Date
        var rolloutURLs: [URL]
    }

    private let sessionsRoot: URL
    private let stateDatabase: URL?
    private let globalStateFile: URL?
    private let sessionIndexFile: URL?
    private let recentFileInterval: TimeInterval
    private let activeStaleInterval: TimeInterval
    private var cache: [URL: CachedRollout] = [:]
    private var lastGlobalStateValues: GlobalStateValues?

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        stateDatabase: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite"),
        globalStateFile: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json"),
        sessionIndexFile: URL? = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl"),
        recentFileInterval: TimeInterval = 7 * 24 * 60 * 60,
        activeStaleInterval: TimeInterval = 30 * 60
    ) {
        self.sessionsRoot = sessionsRoot
        self.stateDatabase = stateDatabase
        self.globalStateFile = globalStateFile
        self.sessionIndexFile = sessionIndexFile
        self.recentFileInterval = recentFileInterval
        self.activeStaleInterval = activeStaleInterval
    }

    public func scan() -> [ActiveThread] {
        scanSnapshot().threads
    }

    public func currentReasoningEffort() -> String? {
        currentThreadReasoningSetting()?.effort
    }

    public func currentThreadReasoningSetting() -> CurrentThreadReasoningSetting? {
        guard let stateDatabase,
              FileManager.default.fileExists(atPath: stateDatabase.path) else {
            return nil
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            stateDatabase.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            return nil
        }
        defer { sqlite3_close(database) }

        let sql = """
        SELECT id, model, reasoning_effort
        FROM threads
        WHERE archived = 0
        ORDER BY COALESCE(recency_at_ms, updated_at_ms, updated_at * 1000) DESC
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW,
              let idText = sqlite3_column_text(statement, 0),
              let modelText = sqlite3_column_text(statement, 1),
              let effortText = sqlite3_column_text(statement, 2) else {
            return nil
        }
        return CurrentThreadReasoningSetting(
            threadID: String(cString: idText),
            model: String(cString: modelText),
            effort: String(cString: effortText)
        )
    }

    public func scanSnapshot() -> RolloutSnapshot {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]
        let cutoff = Date().addingTimeInterval(-recentFileInterval)
        let globalState = globalStateValues(fileManager: fileManager)
        let unreadThreadIDs = globalState.unreadThreadIDs
        let currentThreadNames = sessionIndexThreadNames(fileManager: fileManager)
        var seenURLs = Set<URL>()
        var shortTermLimits: [WeeklyLimitUsage] = []
        var weeklyLimits: [WeeklyLimitUsage] = []
        let visibleThreads: [ActiveThread]

        if let indexedRoots = indexedThreadRoots() {
            visibleThreads = indexedRoots.compactMap { root in
                let records = root.rolloutURLs.compactMap { url in
                    cachedRecord(
                        at: url,
                        allowsSubagent: true,
                        cutoff: cutoff,
                        resourceKeys: resourceKeys,
                        seenURLs: &seenURLs
                    )
                }
                shortTermLimits.append(contentsOf: records.compactMap(\.shortTermLimit))
                weeklyLimits.append(contentsOf: records.compactMap(\.weeklyLimit))
                let activeRecords = records.filter(isRecentlyActive)
                let activeStartedAt = activeRecords.map(\.thread.startedAt).min()
                let isUnread = activeStartedAt == nil && unreadThreadIDs.contains(root.id)
                let lastAssistantResult = records
                    .filter { $0.thread.id == root.id && $0.thread.lastAssistantResult != nil }
                    .max { $0.thread.updatedAt < $1.thread.updatedAt }?
                    .thread.lastAssistantResult

                guard activeStartedAt != nil || isUnread else {
                    return nil
                }
                return ActiveThread(
                    id: root.id,
                    title: currentThreadNames[root.id] ?? root.title,
                    cwd: root.cwd,
                    startedAt: activeStartedAt ?? root.updatedAt,
                    updatedAt: root.updatedAt,
                    projectRecencyAt: root.projectRecencyAt,
                    isActive: activeStartedAt != nil,
                    isUnread: isUnread,
                    lastAssistantResult: lastAssistantResult
                )
            }
        } else {
            var visibleThreadsByID: [String: ActiveThread] = [:]
            for url in fallbackRolloutURLs(fileManager: fileManager, resourceKeys: resourceKeys) {
                guard let record = cachedRecord(
                    at: url,
                    allowsSubagent: false,
                    cutoff: cutoff,
                    resourceKeys: resourceKeys,
                    seenURLs: &seenURLs
                ) else {
                    continue
                }
                if let weeklyLimit = record.weeklyLimit {
                    weeklyLimits.append(weeklyLimit)
                }
                if let shortTermLimit = record.shortTermLimit {
                    shortTermLimits.append(shortTermLimit)
                }
                let isUnread = !record.isActive && unreadThreadIDs.contains(record.thread.id)
                let isActive = isRecentlyActive(record)
                guard isActive || isUnread else {
                    continue
                }
                let visibleThread = ActiveThread(
                    id: record.thread.id,
                    cwd: record.thread.cwd,
                    startedAt: record.thread.startedAt,
                    updatedAt: record.thread.updatedAt,
                    projectRecencyAt: record.thread.projectRecencyAt,
                    isActive: isActive,
                    isUnread: isUnread,
                    lastAssistantResult: record.thread.lastAssistantResult
                )
                let existing = visibleThreadsByID[record.thread.id]
                if existing == nil || visibleThread.updatedAt > existing!.updatedAt {
                    visibleThreadsByID[record.thread.id] = visibleThread
                }
            }
            visibleThreads = Array(visibleThreadsByID.values)
        }

        cache = cache.filter { seenURLs.contains($0.key) }
        let sortedThreads = visibleThreads.sorted {
            if $0.isUnread != $1.isUnread {
                return $0.isUnread
            }
            if $0.startedAt == $1.startedAt {
                return $0.id < $1.id
            }
            return $0.startedAt < $1.startedAt
        }
        let latestWeeklyLimit = weeklyLimits.max {
            $0.recordedAt < $1.recordedAt
        }
        let latestShortTermLimit = shortTermLimits.max {
            $0.recordedAt < $1.recordedAt
        }
        return RolloutSnapshot(
            threads: sortedThreads,
            shortTermLimit: latestShortTermLimit,
            weeklyLimit: latestWeeklyLimit,
            selectedProjectRoots: globalState.selectedProjectRoots
        )
    }

    private func sessionIndexThreadNames(fileManager: FileManager) -> [String: String] {
        guard let sessionIndexFile,
              let data = fileManager.contents(atPath: sessionIndexFile.path),
              let contents = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var names: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData),
                  let entry = object as? [String: Any],
                  let id = entry["id"] as? String,
                  let rawName = entry["thread_name"] as? String else {
                continue
            }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                names[id] = name
            }
        }
        return names
    }

    private func isRecentlyActive(_ record: RolloutRecord) -> Bool {
        record.isActive && Date().timeIntervalSince(record.thread.updatedAt) <= activeStaleInterval
    }

    private func globalStateValues(fileManager: FileManager) -> GlobalStateValues {
        let emptyValues = GlobalStateValues(
            unreadThreadIDs: [],
            selectedProjectRoots: []
        )
        guard let globalStateFile,
              let data = fileManager.contents(atPath: globalStateFile.path),
              let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any] else {
            return lastGlobalStateValues ?? emptyValues
        }

        let atomState = root["electron-persisted-atom-state"] as? [String: Any]
        let unreadByHost = atomState?["unread-thread-ids-by-host-v1"] as? [String: Any]
        let unreadThreadIDs = Set(unreadByHost?["local"] as? [String] ?? [])

        var selectedProjectRoots: [URL] = []
        if let selectedProject = root["selected-project"] as? [String: Any],
           selectedProject["type"] as? String == "local",
           let projectID = selectedProject["projectId"] as? String,
           let localProjects = root["local-projects"] as? [String: Any],
           let localProject = localProjects[projectID] as? [String: Any],
           let rootPaths = localProject["rootPaths"] as? [String] {
            selectedProjectRoots = rootPaths
                .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
                .sorted { $0.path < $1.path }
        }

        let stateValues = GlobalStateValues(
            unreadThreadIDs: unreadThreadIDs,
            selectedProjectRoots: selectedProjectRoots
        )
        lastGlobalStateValues = stateValues
        return stateValues
    }

    private func cachedRecord(
        at fileURL: URL,
        allowsSubagent: Bool,
        cutoff: Date,
        resourceKeys: Set<URLResourceKey>,
        seenURLs: inout Set<URL>
    ) -> RolloutRecord? {
        guard fileURL.pathExtension == "jsonl",
              let values = try? fileURL.resourceValues(forKeys: resourceKeys),
              values.isRegularFile == true,
              let modificationDate = values.contentModificationDate,
              modificationDate >= cutoff else {
            return nil
        }

        let standardizedURL = fileURL.standardizedFileURL
        let fileSize = values.fileSize ?? 0
        seenURLs.insert(standardizedURL)
        let cached = cache[standardizedURL]
        if cached?.modificationDate == modificationDate,
           cached?.fileSize == fileSize,
           cached?.allowsSubagent == allowsSubagent {
            return cached?.record
        }

        if let cached,
           cached.allowsSubagent == allowsSubagent,
           fileSize > cached.fileSize,
           let record = cached.record,
           let update = try? RolloutTailReader.readChanges(
               at: standardizedURL,
               from: cached.processedOffset
           ) {
            let updatedRecord = updateRecord(
                record,
                with: update,
                updatedAt: modificationDate
            )
            cache[standardizedURL] = CachedRollout(
                modificationDate: modificationDate,
                fileSize: fileSize,
                processedOffset: update.processedOffset,
                allowsSubagent: allowsSubagent,
                record: updatedRecord
            )
            return updatedRecord
        }

        let record = parseRollout(
            at: standardizedURL,
            updatedAt: modificationDate,
            allowsSubagent: allowsSubagent
        )
        let processedOffset = (try? RolloutTailReader.endOfLastCompleteLine(
            at: standardizedURL,
            fileSize: UInt64(fileSize)
        )) ?? UInt64(fileSize)
        cache[standardizedURL] = CachedRollout(
            modificationDate: modificationDate,
            fileSize: fileSize,
            processedOffset: processedOffset,
            allowsSubagent: allowsSubagent,
            record: record
        )
        return record
    }

    private func updateRecord(
        _ record: RolloutRecord,
        with update: RolloutTailUpdate,
        updatedAt: Date
    ) -> RolloutRecord {
        let isActive: Bool
        let startedAt: Date
        switch update.latestEvent?.type {
        case "task_started":
            isActive = true
            startedAt = update.latestEvent?.timestamp ?? updatedAt
        case "task_complete", "turn_aborted":
            isActive = false
            startedAt = record.thread.startedAt
        default:
            isActive = record.isActive
            startedAt = record.thread.startedAt
        }

        return RolloutRecord(
            thread: ActiveThread(
                id: record.thread.id,
                cwd: record.thread.cwd,
                startedAt: startedAt,
                updatedAt: updatedAt,
                isActive: isActive,
                lastAssistantResult: update.latestAssistantResult ?? record.thread.lastAssistantResult
            ),
            isActive: isActive,
            shortTermLimit: update.latestShortTermLimit ?? record.shortTermLimit,
            weeklyLimit: update.latestWeeklyLimit ?? record.weeklyLimit
        )
    }

    private func parseRollout(at url: URL, updatedAt: Date, allowsSubagent: Bool) -> RolloutRecord? {
        guard let metadata = readSessionMetadata(at: url), allowsSubagent || !metadata.isSubagent else {
            return nil
        }

        let latestEvents = latestRolloutEvents(at: url)
        let activeStartedAt = latestEvents.task?.type == "task_started"
            ? latestEvents.task?.timestamp ?? updatedAt
            : nil

        let thread = ActiveThread(
            id: metadata.id,
            cwd: metadata.cwd,
            startedAt: activeStartedAt ?? updatedAt,
            updatedAt: updatedAt,
            isActive: activeStartedAt != nil,
            lastAssistantResult: latestEvents.assistantResult
        )
        return RolloutRecord(
            thread: thread,
            isActive: activeStartedAt != nil,
            shortTermLimit: latestEvents.shortTermLimit,
            weeklyLimit: latestEvents.weeklyLimit
        )
    }

    private func fallbackRolloutURLs(
        fileManager: FileManager,
        resourceKeys: Set<URLResourceKey>
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    private func indexedThreadRoots() -> [IndexedThreadRoot]? {
        guard let stateDatabase,
              FileManager.default.fileExists(atPath: stateDatabase.path) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            stateDatabase.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        ) == SQLITE_OK, let database else {
            return nil
        }
        defer { sqlite3_close(database) }

        let query = """
        WITH RECURSIVE recent_members(member_id) AS (
          SELECT id
          FROM threads
          WHERE archived = 0
            AND updated_at >= ?
          UNION
          SELECT edge.parent_thread_id
          FROM recent_members AS recent
          JOIN thread_spawn_edges AS edge ON edge.child_thread_id = recent.member_id
          JOIN threads AS parent ON parent.id = edge.parent_thread_id
          WHERE parent.archived = 0
        ),
        recent_roots(
          root_id,
          root_title,
          root_cwd,
          root_updated,
          root_project_recency_ms
        ) AS (
          SELECT root.id,
                 root.title,
                 root.cwd,
                 root.updated_at,
                 (
                   SELECT MAX(project_thread.recency_at_ms)
                   FROM threads AS project_thread
                   WHERE project_thread.archived = 0
                     AND project_thread.cwd = root.cwd
                 )
          FROM recent_members AS recent
          JOIN threads AS root ON root.id = recent.member_id
          WHERE NOT EXISTS (
            SELECT 1
            FROM thread_spawn_edges AS edge
            WHERE edge.child_thread_id = root.id
          )
          ORDER BY root.updated_at DESC, root.id DESC
          LIMIT 100
        ),
        thread_tree(
          root_id,
          root_title,
          root_cwd,
          root_updated,
          root_project_recency_ms,
          member_id,
          rollout_path,
          member_updated
        ) AS (
          SELECT root.root_id,
                 root.root_title,
                 root.root_cwd,
                 root.root_updated,
                 root.root_project_recency_ms,
                 root.root_id,
                 thread.rollout_path,
                 thread.updated_at
          FROM recent_roots AS root
          JOIN threads AS thread ON thread.id = root.root_id
          UNION ALL
          SELECT tree.root_id, tree.root_title, tree.root_cwd, tree.root_updated,
                 tree.root_project_recency_ms,
                 child.id, child.rollout_path, child.updated_at
          FROM thread_tree AS tree
          JOIN thread_spawn_edges AS edge ON edge.parent_thread_id = tree.member_id
          JOIN threads AS child ON child.id = edge.child_thread_id
          WHERE child.archived = 0
        )
        SELECT tree.root_id,
               tree.root_title,
               tree.root_cwd,
               tree.rollout_path,
               tree.root_updated,
               tree.root_project_recency_ms
        FROM thread_tree AS tree
        ORDER BY tree.root_updated DESC, tree.root_id, tree.member_updated DESC
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        let cutoff = Int64(Date().addingTimeInterval(-recentFileInterval).timeIntervalSince1970)
        sqlite3_bind_int64(statement, 1, cutoff)

        var rootsByID: [String: IndexedThreadRoot] = [:]
        var rootOrder: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPointer = sqlite3_column_text(statement, 0),
                  let titlePointer = sqlite3_column_text(statement, 1),
                  let cwdPointer = sqlite3_column_text(statement, 2),
                  let pathPointer = sqlite3_column_text(statement, 3) else {
                continue
            }
            let id = String(cString: idPointer)
            let rolloutURL = URL(fileURLWithPath: String(cString: pathPointer))
            if rootsByID[id] == nil {
                rootOrder.append(id)
                rootsByID[id] = IndexedThreadRoot(
                    id: id,
                    title: String(cString: titlePointer),
                    cwd: URL(fileURLWithPath: String(cString: cwdPointer), isDirectory: true),
                    updatedAt: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 4))),
                    projectRecencyAt: Date(
                        timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)) / 1_000
                    ),
                    rolloutURLs: [rolloutURL]
                )
            } else {
                rootsByID[id]?.rolloutURLs.append(rolloutURL)
            }
        }
        return rootOrder.compactMap { rootsByID[$0] }
    }

    private func latestRolloutEvents(at url: URL) -> LatestRolloutEvents {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let fileSize = try? handle.seekToEnd() else {
            return LatestRolloutEvents(
                task: nil,
                shortTermLimit: nil,
                weeklyLimit: nil,
                assistantResult: nil
            )
        }
        defer { try? handle.close() }

        let chunkSize: UInt64 = 256 * 1_024
        let newline = UInt8(ascii: "\n")
        var position = fileSize
        var leadingFragment = Data()
        var latestTask: RolloutTaskEvent?
        var latestShortTermLimit: WeeklyLimitUsage?
        var latestWeeklyLimit: WeeklyLimitUsage?
        var latestAssistantResult: String?

        while position > 0 {
            let readStart = position > chunkSize ? position - chunkSize : 0
            let readCount = Int(position - readStart)
            do {
                try handle.seek(toOffset: readStart)
                guard let chunk = try handle.read(upToCount: readCount) else {
                    return LatestRolloutEvents(
                        task: latestTask,
                        shortTermLimit: latestShortTermLimit,
                        weeklyLimit: latestWeeklyLimit,
                        assistantResult: latestAssistantResult
                    )
                }

                var combined = chunk
                combined.append(leadingFragment)
                var lines = combined.split(separator: newline, omittingEmptySubsequences: true)

                if readStart > 0, !lines.isEmpty {
                    leadingFragment = Data(lines.removeFirst())
                } else {
                    leadingFragment.removeAll(keepingCapacity: true)
                }

                for line in lines.reversed() {
                    let events = RolloutTailReader.lineEvents(in: Data(line))
                    latestTask = latestTask ?? events.task
                    latestShortTermLimit = latestShortTermLimit ?? events.shortTermLimit
                    latestWeeklyLimit = latestWeeklyLimit ?? events.weeklyLimit
                    latestAssistantResult = latestAssistantResult
                        ?? RolloutTailReader.assistantResult(in: Data(line))
                    if latestTask != nil,
                       latestShortTermLimit != nil,
                       latestWeeklyLimit != nil,
                       latestAssistantResult != nil {
                        return LatestRolloutEvents(
                            task: latestTask,
                            shortTermLimit: latestShortTermLimit,
                            weeklyLimit: latestWeeklyLimit,
                            assistantResult: latestAssistantResult
                        )
                    }
                }
            } catch {
                return LatestRolloutEvents(
                    task: latestTask,
                    shortTermLimit: latestShortTermLimit,
                    weeklyLimit: latestWeeklyLimit,
                    assistantResult: latestAssistantResult
                )
            }
            position = readStart
        }
        if !leadingFragment.isEmpty {
            let events = RolloutTailReader.lineEvents(in: leadingFragment)
            latestTask = latestTask ?? events.task
            latestShortTermLimit = latestShortTermLimit ?? events.shortTermLimit
            latestWeeklyLimit = latestWeeklyLimit ?? events.weeklyLimit
            latestAssistantResult = latestAssistantResult
                ?? RolloutTailReader.assistantResult(in: leadingFragment)
        }
        return LatestRolloutEvents(
            task: latestTask,
            shortTermLimit: latestShortTermLimit,
            weeklyLimit: latestWeeklyLimit,
            assistantResult: latestAssistantResult
        )
    }

    private func readSessionMetadata(at url: URL) -> (id: String, cwd: URL, isSubagent: Bool)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }

        var lineData = Data()
        let newline = UInt8(ascii: "\n")
        let maximumMetadataBytes = 8 * 1_024 * 1_024

        while lineData.count < maximumMetadataBytes {
            guard let chunk = try? handle.read(upToCount: 64 * 1_024),
                  !chunk.isEmpty else {
                break
            }
            lineData.append(chunk)
            if let newlineIndex = lineData.firstIndex(of: newline) {
                lineData = lineData.prefix(upTo: newlineIndex)
                break
            }
        }

        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "session_meta",
              let payload = envelope["payload"] as? [String: Any],
              let id = payload["id"] as? String,
              let cwd = payload["cwd"] as? String else {
            return nil
        }

        return (
            id: id,
            cwd: URL(fileURLWithPath: cwd, isDirectory: true),
            isSubagent: payload["thread_source"] as? String == "subagent"
        )
    }

}
