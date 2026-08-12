@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func viewedThreadStoreMarksSeveralThreadsAtomically() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let file = directory.appendingPathComponent("viewed.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let viewedAt = Date(timeIntervalSince1970: 1_000)

    try ViewedThreadStore.markViewed(
        threadIDs: ["first", "second"],
        at: viewedAt,
        file: file
    )

    let values = ViewedThreadStore.viewedAtByThreadID(file: file)
    #expect(values == ["first": viewedAt, "second": viewedAt])
}
