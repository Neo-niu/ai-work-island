import Foundation
import Testing
@testable import CodexTouchBarCore

@Test func meetingTodoQueueReadsPendingAndDeletesExpiredCandidates() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let valid = root.appendingPathComponent("valid.json")
    let expired = root.appendingPathComponent("expired.json")
    try payload(id: "valid", created: now.addingTimeInterval(-10), expires: now.addingTimeInterval(60))
        .write(to: valid)
    try payload(id: "expired", created: now.addingTimeInterval(-20), expires: now.addingTimeInterval(-1))
        .write(to: expired)

    let queue = MeetingTodoConfirmationQueue(pendingDirectory: root, now: { now })
    let candidates = queue.pendingCandidates()
    #expect(candidates.map(\.id) == ["valid"])
    #expect(!FileManager.default.fileExists(atPath: expired.path))
    try queue.discard(candidates[0])
    #expect(queue.pendingCandidates().isEmpty)
}

private func payload(id: String, created: Date, expires: Date) -> Data {
    let formatter = ISO8601DateFormatter()
    let object: [String: Any] = [
        "id": id,
        "title": "完成文档",
        "owner": "张三",
        "dueDate": "2026-09-02",
        "meetingTitle": "产品周会",
        "meetingDate": "2026-08-31",
        "notePath": "/tmp/产品周会.md",
        "createdAt": formatter.string(from: created),
        "expiresAt": formatter.string(from: expires),
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}
