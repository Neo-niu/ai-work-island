import Foundation
import Testing
@testable import CodexTouchBarCore

@Test func createdThreadStaysVisibleAcrossIndexingGapUntilUnreadAppears() {
    let now = Date(timeIntervalSince1970: 1_000)
    let fallback = ActiveThread(
        id: "created-thread",
        title: "新任务",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: now,
        updatedAt: now
    )
    var pending = [
        fallback.id: PendingCreatedThread(
            thread: fallback,
            expiresAt: now.addingTimeInterval(1_800)
        ),
    ]

    var result = CreatedThreadContinuity.reconcile(
        scannedThreads: [],
        pending: pending,
        now: now
    )
    #expect(result.threads == [fallback])
    #expect(result.pending.keys.contains(fallback.id))

    result = CreatedThreadContinuity.reconcile(
        scannedThreads: [fallback],
        pending: result.pending,
        now: now.addingTimeInterval(1)
    )
    #expect(result.pending.keys.contains(fallback.id))

    pending = result.pending
    result = CreatedThreadContinuity.reconcile(
        scannedThreads: [],
        pending: pending,
        now: now.addingTimeInterval(2)
    )
    #expect(result.threads == [fallback])

    let completed = ActiveThread(
        id: fallback.id,
        title: fallback.title,
        cwd: fallback.cwd,
        startedAt: fallback.startedAt,
        updatedAt: now.addingTimeInterval(3),
        isActive: false,
        isUnread: true,
        lastAssistantResult: "完成"
    )
    result = CreatedThreadContinuity.reconcile(
        scannedThreads: [completed],
        pending: result.pending,
        now: now.addingTimeInterval(3)
    )
    #expect(result.threads == [completed])
    #expect(result.pending.isEmpty)
}

@Test func createdThreadFallbackExpiresInsteadOfStayingActiveForever() {
    let now = Date(timeIntervalSince1970: 2_000)
    let fallback = ActiveThread(
        id: "expired-thread",
        cwd: URL(fileURLWithPath: "/tmp/project"),
        startedAt: now.addingTimeInterval(-60),
        updatedAt: now.addingTimeInterval(-60)
    )
    let result = CreatedThreadContinuity.reconcile(
        scannedThreads: [],
        pending: [
            fallback.id: PendingCreatedThread(
                thread: fallback,
                expiresAt: now
            ),
        ],
        now: now
    )
    #expect(result.threads.isEmpty)
    #expect(result.pending.isEmpty)
}
