@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func refreshPolicyPollsWheneverTheDashboardIsVisible() {
    #expect(RefreshPolicy.pollInterval(isDashboardVisible: true, hasActiveWork: false) == 1)
    #expect(RefreshPolicy.pollInterval(isDashboardVisible: false, hasActiveWork: true) == 3)
    #expect(RefreshPolicy.pollInterval(isDashboardVisible: false, hasActiveWork: false) == 30)
}

@Test func widgetReloadIntervalAdaptsToWorkState() {
    let date = Date(timeIntervalSince1970: 1)
    func item(_ status: WorkItemStatus) -> WorkItem {
        WorkItem(id: status.rawValue, source: "test", title: "test", status: status, updatedAt: date)
    }
    #expect(RefreshPolicy.widgetReloadInterval(items: [item(.running)]) == 300)
    #expect(RefreshPolicy.widgetReloadInterval(items: [item(.waiting)]) == 600)
    #expect(RefreshPolicy.widgetReloadInterval(items: [item(.queued)]) == 300)
    #expect(RefreshPolicy.widgetReloadInterval(items: [item(.idle)]) == 1_800)
}

@Test func refreshTimerRunsDuringTouchBarEventTracking() {
    #expect(RefreshPolicy.timerRunLoopMode == .common)
}

@Test func refreshPolicySkipsAnUnchangedTouchBarModel() {
    let thread = ActiveThread(
        id: "thread",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 2)
    )
    let groups = [ProjectGroup(
        id: "/tmp/project",
        name: "project",
        threads: [thread],
        isUnnamed: false
    )]

    #expect(RefreshPolicy.shouldApply(previous: nil, next: groups))
    #expect(!RefreshPolicy.shouldApply(previous: groups, next: groups))
}
