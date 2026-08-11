import Foundation

public enum RefreshPolicy {
    public static let timerRunLoopMode = RunLoop.Mode.common

    public static func pollInterval(
        isDashboardVisible: Bool,
        hasActiveWork: Bool
    ) -> TimeInterval {
        if isDashboardVisible { return 1 }
        return hasActiveWork ? 3 : 30
    }

    public static func shouldApply(previous: [ProjectGroup]?, next: [ProjectGroup]) -> Bool {
        previous != next
    }
}
