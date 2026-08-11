import Foundation

public enum WorkItemStatus: String, Codable, CaseIterable, Sendable {
    case running
    case queued
    case waiting
    case failed
    case completed
    case idle
    case stale

    public var priority: Int {
        switch self {
        case .waiting: 0
        case .failed, .stale: 1
        case .queued: 2
        case .running: 3
        case .completed: 4
        case .idle: 5
        }
    }

    public var requiresAttention: Bool {
        self == .failed || self == .stale
    }

    public var isActiveWork: Bool {
        self == .running || self == .queued
    }
}

public struct WorkItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let source: String
    public let title: String
    public let detail: String?
    public let status: WorkItemStatus
    public let startedAt: Date?
    public let updatedAt: Date
    public let outputPath: String?
    public let openURL: String?
    public let phase: String?
    public let phaseIndex: Int?
    public let phaseCount: Int?

    public init(
        id: String,
        source: String,
        title: String,
        detail: String? = nil,
        status: WorkItemStatus,
        startedAt: Date? = nil,
        updatedAt: Date,
        outputPath: String? = nil,
        openURL: String? = nil,
        phase: String? = nil,
        phaseIndex: Int? = nil,
        phaseCount: Int? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.outputPath = outputPath
        self.openURL = openURL
        self.phase = phase
        self.phaseIndex = phaseIndex
        self.phaseCount = phaseCount
    }
}

public extension WorkItem {
    var displayTitle: String {
        let ignoredPrefixes = [
            "codex-clipboard-",
            "files mentioned by the user",
            "my request",
            "image name=",
        ]
        for rawLine in title.components(separatedBy: .newlines) {
            let line = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(
                    of: #"^(?:#{1,6}|[-*])\s*"#,
                    with: "",
                    options: .regularExpression
                )
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let normalized = line.lowercased()
            guard !ignoredPrefixes.contains(where: normalized.hasPrefix) else { continue }
            return line
        }
        return source
    }

    var displayDetail: String {
        let value = detail ?? source
        return value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

public struct WorkStatusSnapshot: Equatable, Sendable {
    public let items: [WorkItem]
    public let automationIssues: [String]
    public let codexShortTermLimit: WeeklyLimitUsage?
    public let codexWeeklyLimit: WeeklyLimitUsage?
    public let companyQuota: CompanyModelQuota?
    public let refreshedAt: Date

    public init(
        items: [WorkItem],
        automationIssues: [String],
        codexShortTermLimit: WeeklyLimitUsage? = nil,
        codexWeeklyLimit: WeeklyLimitUsage? = nil,
        companyQuota: CompanyModelQuota? = nil,
        refreshedAt: Date = Date()
    ) {
        self.items = items
        self.automationIssues = automationIssues
        self.codexShortTermLimit = codexShortTermLimit
        self.codexWeeklyLimit = codexWeeklyLimit
        self.companyQuota = companyQuota
        self.refreshedAt = refreshedAt
    }
}

public enum WorkStatusHub {
    public static func latestCompletedOpenableItem(from items: [WorkItem]) -> WorkItem? {
        items
            .filter { item in
                item.status == .completed
                    && (item.id.hasPrefix("codex:") || item.openURL != nil || item.outputPath != nil)
            }
            .max { $0.updatedAt < $1.updatedAt }
    }

    public static func codexItems(from groups: [ProjectGroup]) -> [WorkItem] {
        groups.flatMap { group in
            group.threads.map { thread in
                WorkItem(
                    id: "codex:\(thread.id)",
                    source: "Codex",
                    title: thread.title ?? group.name,
                    detail: thread.isActive ? "正在处理 · \(group.name)" : "等待查看 · \(group.name)",
                    status: thread.isActive ? .running : .waiting,
                    startedAt: thread.startedAt,
                    updatedAt: thread.updatedAt
                )
            }
        }
    }

    public static func merge(codex: [WorkItem], automation: [WorkItem]) -> [WorkItem] {
        (codex + automation).sorted { lhs, rhs in
            if lhs.status.priority != rhs.status.priority {
                return lhs.status.priority < rhs.status.priority
            }
            let sortsByRecency = lhs.status == .completed || lhs.status == .idle
            if sortsByRecency, lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.id < rhs.id
        }
    }
}
