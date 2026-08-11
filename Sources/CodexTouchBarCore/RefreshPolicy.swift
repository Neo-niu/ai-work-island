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

    public static func widgetReloadInterval(items: [WorkItem]) -> TimeInterval {
        if items.contains(where: { $0.status.isActiveWork }) { return 5 * 60 }
        if items.contains(where: {
            $0.status == .waiting || $0.status == .failed || $0.status == .stale
        }) { return 10 * 60 }
        return 30 * 60
    }

    public static func shouldApply(previous: [ProjectGroup]?, next: [ProjectGroup]) -> Bool {
        previous != next
    }
}
