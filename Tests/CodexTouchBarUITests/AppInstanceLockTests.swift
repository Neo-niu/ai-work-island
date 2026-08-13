import Foundation
@testable import CodexTouchBar
import Testing

@Test func backgroundReopenDoesNotRestoreTheDashboard() {
    #expect(!AppReopenPolicy.shouldRestoreDashboard)
}

@Test func appInstanceLockRejectsASecondProcessLock() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let lockFile = directory.appendingPathComponent("app-instance.lock")
    defer { try? FileManager.default.removeItem(at: directory) }

    let first = try #require(AppInstanceLock.acquire(at: lockFile))
    #expect(AppInstanceLock.acquire(at: lockFile) == nil)

    first.release()
    #expect(AppInstanceLock.acquire(at: lockFile) != nil)
}
