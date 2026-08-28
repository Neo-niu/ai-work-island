@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func refreshPolicyPollsWheneverTheDashboardIsVisible() {
    #expect(RefreshPolicy.pollInterval(isDashboardVisible: true, hasActiveWork: false) == 1)
    #expect(RefreshPolicy.pollInterval(isDashboardVisible: false, hasActiveWork: true) == 3)
    #expect(RefreshPolicy.pollInterval(isDashboardVisible: false, hasActiveWork: false) == 30)
}

@Test func refreshTimerRunsDuringTouchBarEventTracking() {
    #expect(RefreshPolicy.timerRunLoopMode == .common)
}

@Test func invalidRefreshTimerIsReplacedEvenWhenItsIntervalDidNotChange() {
    #expect(RefreshPolicy.shouldReplaceTimer(
        scheduledInterval: 1,
        desiredInterval: 1,
        timerIsValid: false
    ))
    #expect(!RefreshPolicy.shouldReplaceTimer(
        scheduledInterval: 1,
        desiredInterval: 1,
        timerIsValid: true
    ))
}

@Test func companyQuotaRefreshesEveryFiveMinutes() {
    #expect(RefreshPolicy.companyQuotaInterval == 300)
}

@Test func regularPollingCannotDelayCompanyQuotaPastItsRefreshInterval() {
    let slowestRegularPoll = RefreshPolicy.pollInterval(
        isDashboardVisible: false,
        hasActiveWork: false
    )
    #expect(slowestRegularPoll < RefreshPolicy.companyQuotaInterval)
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
