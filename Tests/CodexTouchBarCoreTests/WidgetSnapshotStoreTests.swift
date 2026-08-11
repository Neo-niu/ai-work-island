@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func widgetSnapshotRoundTripsWithoutConversationContent() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let url = directory.appendingPathComponent("widget-snapshot.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let date = Date(timeIntervalSince1970: 100)
    let startedAt = Date(timeIntervalSince1970: 50)
    let snapshot = WidgetStatusSnapshot(items: [
        WorkItem(
            id: "automation:daily",
            source: "自动化",
            title: "下载数据并合并",
            detail: "等待下次运行",
            status: .idle,
            startedAt: startedAt,
            updatedAt: date,
            outputPath: "/tmp/output"
        ),
    ], refreshedAt: date)
    let store = WidgetSnapshotStore(snapshotURL: url)

    try store.write(snapshot)

    #expect(try store.read() == snapshot)
    #expect(try store.read().items.first?.startedAt == startedAt)
    #expect(FileManager.default.fileExists(atPath: url.path))
}
