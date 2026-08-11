import CSQLite
import Foundation

public struct HermesStatus: Equatable, Sendable {
    public let gatewayRunning: Bool
    public let connectedPlatforms: Int
    public let runningTasks: Int
    public let blockedTasks: Int
    public let failedTasks: Int

    public init(
        gatewayRunning: Bool,
        connectedPlatforms: Int,
        runningTasks: Int,
        blockedTasks: Int,
        failedTasks: Int
    ) {
        self.gatewayRunning = gatewayRunning
        self.connectedPlatforms = connectedPlatforms
        self.runningTasks = runningTasks
        self.blockedTasks = blockedTasks
        self.failedTasks = failedTasks
    }

    public var needsAttention: Bool { blockedTasks > 0 || failedTasks > 0 }

    public var compactTitle: String {
        if blockedTasks > 0 { return "Hermes !\(blockedTasks)" }
        if failedTasks > 0 { return "Hermes ×\(failedTasks)" }
        if runningTasks > 0 { return "Hermes · \(runningTasks)" }
        return gatewayRunning ? "Hermes ✓" : "Hermes —"
    }
}

public struct HermesStatusScanner: Sendable {
    private let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory
    }

    public func scan() -> HermesStatus {
        let hermesHome = homeDirectory.appendingPathComponent(".hermes", isDirectory: true)
        let gateway = readGateway(at: hermesHome.appendingPathComponent("gateway_state.json"))
        let tasks = readTaskCounts(at: hermesHome.appendingPathComponent("kanban.db"))
        return HermesStatus(
            gatewayRunning: gateway.running,
            connectedPlatforms: gateway.connectedPlatforms,
            runningTasks: tasks.running,
            blockedTasks: tasks.blocked,
            failedTasks: tasks.failed
        )
    }

    private func readGateway(at url: URL) -> (running: Bool, connectedPlatforms: Int) {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, 0)
        }
        let running = root["gateway_state"] as? String == "running"
        let platforms = root["platforms"] as? [String: Any] ?? [:]
        let connected = platforms.values.reduce(into: 0) { count, value in
            guard let platform = value as? [String: Any],
                  platform["state"] as? String == "connected" else { return }
            count += 1
        }
        return (running, connected)
    }

    private func readTaskCounts(at url: URL) -> (running: Int, blocked: Int, failed: Int) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return (0, 0, 0)
        }
        defer { sqlite3_close(database) }

        let query = "SELECT status, COUNT(*) FROM tasks WHERE status IN ('doing','running','blocked','triage','failed') GROUP BY status"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return (0, 0, 0) }
        defer { sqlite3_finalize(statement) }

        var running = 0
        var blocked = 0
        var failed = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawStatus = sqlite3_column_text(statement, 0) else { continue }
            let status = String(cString: rawStatus)
            let count = Int(sqlite3_column_int(statement, 1))
            switch status {
            case "doing", "running": running += count
            case "blocked", "triage": blocked += count
            case "failed": failed += count
            default: break
            }
        }
        return (running, blocked, failed)
    }
}
