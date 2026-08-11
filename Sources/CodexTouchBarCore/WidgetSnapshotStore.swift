import Foundation

public enum WidgetStatusConfiguration {
    public static let kind = "CodexStatusWidget"
    public static let urlScheme = "codexhermestouchbar"
    public static let statusURL = URL(string: "\(urlScheme)://status")!
    public static let recordURL = URL(string: "\(urlScheme)://record")!
    public static let refreshURL = URL(string: "\(urlScheme)://refresh")!
}

public struct WidgetStatusSnapshot: Codable, Equatable, Sendable {
    public let items: [WorkItem]
    public let refreshedAt: Date

    public init(items: [WorkItem], refreshedAt: Date = Date()) {
        self.items = items
        self.refreshedAt = refreshedAt
    }
}

public struct WidgetSnapshotStore: Sendable {
    public static let widgetBundleIdentifier =
        "dev.kanyun.CodexHermesTouchBar.CodexStatusWidget"

    public let snapshotURL: URL

    public init(
        snapshotURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers", isDirectory: true)
            .appendingPathComponent(widgetBundleIdentifier, isDirectory: true)
            .appendingPathComponent("Data/Library/Application Support", isDirectory: true)
            .appendingPathComponent("Codex Hermes Touch Bar", isDirectory: true)
            .appendingPathComponent("widget-snapshot.json")
    ) {
        self.snapshotURL = snapshotURL
    }

    public func write(_ snapshot: WidgetStatusSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: snapshotURL, options: .atomic)
    }

    public func read() throws -> WidgetStatusSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            WidgetStatusSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
    }
}
