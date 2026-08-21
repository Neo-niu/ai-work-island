import Foundation

public struct CodexCardStatusSummary: Equatable, Sendable {
    public let entries: [String]
    public let progressText: String?

    public init(entries: [String], progressText: String? = nil) {
        self.entries = entries
        self.progressText = progressText
    }

    public var text: String {
        entries.joined(separator: "\n")
    }

    public var detailedText: String { text }

    public static func running(
        phase: String?,
        completedSteps: Int?,
        totalSteps: Int?,
        recentActivity: String?,
        activities: [String] = []
    ) -> CodexCardStatusSummary {
        var candidates = activities.compactMap(normalizedActivity)
        if candidates.isEmpty {
            candidates = [recentActivity, phase].compactMap(normalizedActivity)
        }
        var seen = Set<String>()
        let entries = candidates.filter { seen.insert($0).inserted }.suffix(4)
        let progressText: String?
        if let totalSteps, totalSteps > 0 {
            let completed = min(max(completedSteps ?? 0, 0), totalSteps)
            progressText = "\(completed)/\(totalSteps) 个步骤"
        } else {
            progressText = nil
        }
        return CodexCardStatusSummary(
            entries: entries.isEmpty ? ["正在思考"] : Array(entries),
            progressText: progressText
        )
    }

    public static func waiting(lastAssistantResult: String?) -> CodexCardStatusSummary {
        let result = lastAssistantResult?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexCardStatusSummary(
            entries: [(result?.isEmpty == false ? result : nil) ?? "任务已完成，等待查看"]
        )
    }

    private static func normalizedActivity(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        for prefix in [
            "正在操作：", "正在操作", "操作：",
            "正在：", "当前：", "刚刚：", "最新：",
            "正在", "当前", "刚刚", "最新",
        ] {
            if value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return value.isEmpty ? nil : value
    }
}
