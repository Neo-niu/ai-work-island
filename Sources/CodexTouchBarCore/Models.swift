import Foundation

public struct CurrentThreadReasoningSetting: Equatable, Sendable {
    public let threadID: String
    public let model: String
    public let effort: String

    public init(threadID: String, model: String, effort: String) {
        self.threadID = threadID
        self.model = model
        self.effort = effort
    }
}

public struct WeeklyLimitUsage: Equatable, Sendable {
    public let usedPercent: Double
    public let resetsAt: Date?
    public let recordedAt: Date

    public init(usedPercent: Double, resetsAt: Date?, recordedAt: Date) {
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.recordedAt = recordedAt
    }

    public var remainingPercent: Int {
        Int((100 - min(max(usedPercent, 0), 100)).rounded())
    }
}

public struct RolloutSnapshot: Equatable, Sendable {
    public let threads: [ActiveThread]
    public let shortTermLimit: WeeklyLimitUsage?
    public let weeklyLimit: WeeklyLimitUsage?
    public let selectedProjectRoots: [URL]

    public init(
        threads: [ActiveThread],
        shortTermLimit: WeeklyLimitUsage? = nil,
        weeklyLimit: WeeklyLimitUsage?,
        selectedProjectRoots: [URL] = []
    ) {
        self.threads = threads
        self.shortTermLimit = shortTermLimit
        self.weeklyLimit = weeklyLimit
        self.selectedProjectRoots = selectedProjectRoots
    }
}

public struct ActiveThread: Equatable, Sendable {
    public let id: String
    public let title: String?
    public let cwd: URL
    public let startedAt: Date
    public let updatedAt: Date
    public let projectRecencyAt: Date
    public let isActive: Bool
    public let isUnread: Bool
    public let lastAssistantResult: String?

    public init(
        id: String,
        title: String? = nil,
        cwd: URL,
        startedAt: Date,
        updatedAt: Date,
        projectRecencyAt: Date? = nil,
        isActive: Bool = true,
        isUnread: Bool = false,
        lastAssistantResult: String? = nil
    ) {
        self.id = id
        self.title = title
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.projectRecencyAt = projectRecencyAt ?? updatedAt
        self.isActive = isActive
        self.isUnread = isUnread
        self.lastAssistantResult = lastAssistantResult
    }
}

public struct ProjectGroup: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let threads: [ActiveThread]
    public let isUnnamed: Bool
    public let hasUnread: Bool
    public let isSelected: Bool

    public init(
        id: String,
        name: String,
        threads: [ActiveThread],
        isUnnamed: Bool,
        hasUnread: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.threads = threads
        self.isUnnamed = isUnnamed
        self.hasUnread = hasUnread
        self.isSelected = isSelected
    }

    public func displayName(maxLength: Int = 20) -> String {
        guard maxLength > 1, name.count > maxLength else {
            return name
        }
        return String(name.prefix(maxLength - 1)) + "…"
    }
}

public struct ThreadCycler: Sendable {
    private var nextIndexes: [String: Int] = [:]

    public init() {}

    public mutating func nextThread(in group: ProjectGroup) -> ActiveThread? {
        guard !group.threads.isEmpty else {
            nextIndexes[group.id] = nil
            return nil
        }

        let nextIndex = (nextIndexes[group.id] ?? 0) % group.threads.count
        nextIndexes[group.id] = (nextIndex + 1) % group.threads.count
        return group.threads[nextIndex]
    }

    public mutating func retainGroups(_ groupIDs: Set<String>) {
        nextIndexes = nextIndexes.filter { groupIDs.contains($0.key) }
    }
}

public enum ThreadStatusCategory: Hashable, Sendable {
    case processing
    case unread
}

public struct ThreadStatusCycler: Sendable {
    private var nextIndexes: [ThreadStatusCategory: Int] = [:]

    public init() {}

    public mutating func nextThread(
        in groups: [ProjectGroup],
        category: ThreadStatusCategory
    ) -> ActiveThread? {
        let candidates = groups.flatMap(\.threads).filter { thread in
            switch category {
            case .processing:
                thread.isActive
            case .unread:
                thread.isUnread
            }
        }
        guard !candidates.isEmpty else {
            nextIndexes[category] = nil
            return nil
        }

        let nextIndex = (nextIndexes[category] ?? 0) % candidates.count
        nextIndexes[category] = (nextIndex + 1) % candidates.count
        return candidates[nextIndex]
    }
}
