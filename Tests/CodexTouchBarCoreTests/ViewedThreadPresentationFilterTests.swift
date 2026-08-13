import Foundation
import Testing
@testable import CodexTouchBarCore

@Test func optimisticallyViewedUnreadThreadDisappearsImmediately() {
    let viewedAt = Date()
    let unread = ActiveThread(
        id: "unread",
        title: "Unread",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(),
        updatedAt: viewedAt.addingTimeInterval(-1),
        isActive: false,
        isUnread: true
    )
    let active = ActiveThread(
        id: "active",
        title: "Active",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: Date(),
        updatedAt: viewedAt.addingTimeInterval(-1),
        isActive: true,
        isUnread: true
    )
    let group = ProjectGroup(
        id: "project",
        name: "Project",
        threads: [unread, active],
        isUnnamed: false,
        hasUnread: true
    )

    let filtered = ViewedThreadPresentationFilter.filtering(
        [group],
        viewedAtByThreadID: ["unread": viewedAt, "active": viewedAt]
    )

    #expect(filtered.flatMap(\.threads).map(\.id) == ["active"])
    #expect(filtered.first?.hasUnread == true)
}

@Test func aNewerResultRestoresTheWaitingReminder() {
    let viewedAt = Date()
    let newerResult = ActiveThread(
        id: "newer",
        title: "New result",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: viewedAt.addingTimeInterval(-10),
        updatedAt: viewedAt.addingTimeInterval(1),
        isActive: false,
        isUnread: true
    )
    let group = ProjectGroup(
        id: "project",
        name: "Project",
        threads: [newerResult],
        isUnnamed: false,
        hasUnread: true
    )

    let filtered = ViewedThreadPresentationFilter.filtering(
        [group],
        viewedAtByThreadID: ["newer": viewedAt]
    )

    #expect(filtered.flatMap(\.threads).map(\.id) == ["newer"])
}

@Test func cancellingAnOptimisticViewRestoresTheWaitingReminder() {
    let now = Date()
    let unread = ActiveThread(
        id: "retry",
        title: "Retry",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: now.addingTimeInterval(-10),
        updatedAt: now.addingTimeInterval(-1),
        isActive: false,
        isUnread: true
    )
    let group = ProjectGroup(
        id: "project",
        name: "Project",
        threads: [unread],
        isUnnamed: false,
        hasUnread: true
    )

    let filtered = ViewedThreadPresentationFilter.filtering(
        [group],
        viewedAtByThreadID: [:]
    )

    #expect(filtered.flatMap(\.threads).map(\.id) == ["retry"])
}
