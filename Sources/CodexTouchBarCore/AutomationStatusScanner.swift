import Foundation

public struct AutomationScanResult: Equatable, Sendable {
    public let items: [WorkItem]
    public let issues: [String]

    public init(items: [WorkItem], issues: [String]) {
        self.items = items
        self.issues = issues
    }
}

public struct AutomationStatusScanner: Sendable {
    public static let defaultStaleInterval: TimeInterval = 30 * 60

    public let statusDirectory: URL
    private let now: @Sendable () -> Date

    public init(
        statusDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Hermes Touch Bar/automation-status", isDirectory: true),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.statusDirectory = statusDirectory
        self.now = now
    }

    public func scan() -> AutomationScanResult {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(
            at: statusDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AutomationScanResult(items: [], issues: [])
        }

        var items: [WorkItem] = []
        var issues: [String] = []
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where url.pathExtension.lowercased() == "json" {
            do {
                items.append(try readItem(at: url, fileManager: fileManager))
            } catch {
                issues.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return AutomationScanResult(items: items, issues: issues)
    }

    private func readItem(at url: URL, fileManager: FileManager) throws -> WorkItem {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(AutomationStatusPayload.self, from: data)
        let modificationDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        let updatedAt = payload.updatedAt ?? modificationDate ?? now()
        let status: WorkItemStatus
        if payload.status == .running,
           payload.staleAfterSeconds != 0,
           now().timeIntervalSince(updatedAt) > (payload.staleAfterSeconds ?? Self.defaultStaleInterval) {
            status = .stale
        } else {
            status = payload.status
        }

        return WorkItem(
            id: "automation:\(payload.id)",
            source: payload.source ?? "自动化",
            title: payload.title,
            detail: payload.detail,
            status: status,
            startedAt: payload.startedAt,
            updatedAt: updatedAt,
            outputPath: payload.outputPath,
            openURL: payload.openURL,
            phase: payload.phase,
            phaseIndex: payload.phaseIndex,
            phaseCount: payload.phaseCount
        )
    }
}

private struct AutomationStatusPayload: Decodable {
    let id: String
    let source: String?
    let title: String
    let detail: String?
    let status: WorkItemStatus
    let startedAt: Date?
    let updatedAt: Date?
    let staleAfterSeconds: TimeInterval?
    let outputPath: String?
    let openURL: String?
    let phase: String?
    let phaseIndex: Int?
    let phaseCount: Int?
}
