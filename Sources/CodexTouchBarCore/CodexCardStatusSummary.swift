import Foundation

public struct CodexCardStatusSummary: Equatable, Sendable {
    public let primary: String
    public let secondary: String?

    public init(primary: String, secondary: String? = nil) {
        self.primary = primary
        self.secondary = secondary
    }

    public var text: String {
        [primary, secondary].compactMap { $0 }.joined(separator: "\n")
    }

    public static func running(
        phase: String?,
        completedSteps: Int?,
        totalSteps: Int?,
        recentActivity: String?
    ) -> CodexCardStatusSummary {
        let normalizedPhase = normalizedActivity(phase)
        let normalizedRecent = normalizedActivity(recentActivity)
        var primaryParts: [String] = []
        if let totalSteps, totalSteps > 0 {
            let completed = min(max(completedSteps ?? 0, 0), totalSteps)
            primaryParts.append("进度 \(completed)/\(totalSteps)")
        }
        if let normalizedPhase {
            primaryParts.append("当前：\(normalizedPhase)")
        }
        let primary = primaryParts.isEmpty
            ? "当前：等待新的运行动态"
            : primaryParts.joined(separator: " · ")
        let secondary = normalizedRecent.flatMap { recent in
            recent == normalizedPhase ? nil : "最新：\(recent)"
        }
        return CodexCardStatusSummary(primary: primary, secondary: secondary)
    }

    public static func waiting(lastAssistantResult: String?) -> CodexCardStatusSummary {
        let result = lastAssistantResult?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexCardStatusSummary(
            primary: "需要你：查看结果并决定下一步",
            secondary: "结果：\((result?.isEmpty == false ? result : nil) ?? "暂无可显示结果")"
        )
    }

    private static func normalizedActivity(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        for prefix in ["正在：", "正在", "当前：", "当前", "刚刚：", "刚刚", "最新：", "最新"] {
            if value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                value = value.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return value.isEmpty ? nil : value
    }
}
