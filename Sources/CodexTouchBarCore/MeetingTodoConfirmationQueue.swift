import Foundation

public struct MeetingTodoCandidate: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let owner: String
    public let dueDate: String
    public let meetingTitle: String
    public let meetingDate: String
    public let notePath: String
    public let createdAt: Date
    public let expiresAt: Date
    public let fileURL: URL

    private enum CodingKeys: String, CodingKey {
        case id, title, owner, dueDate, meetingTitle, meetingDate, notePath, createdAt, expiresAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        owner = try values.decodeIfPresent(String.self, forKey: .owner) ?? ""
        dueDate = try values.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        meetingTitle = try values.decode(String.self, forKey: .meetingTitle)
        meetingDate = try values.decode(String.self, forKey: .meetingDate)
        notePath = try values.decode(String.self, forKey: .notePath)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        fileURL = decoder.userInfo[.meetingTodoFileURL] as? URL ?? URL(fileURLWithPath: "/dev/null")
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(owner, forKey: .owner)
        try values.encode(dueDate, forKey: .dueDate)
        try values.encode(meetingTitle, forKey: .meetingTitle)
        try values.encode(meetingDate, forKey: .meetingDate)
        try values.encode(notePath, forKey: .notePath)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(expiresAt, forKey: .expiresAt)
    }
}

private extension CodingUserInfoKey {
    static let meetingTodoFileURL = CodingUserInfoKey(rawValue: "meetingTodoFileURL")!
}

public struct MeetingTodoConfirmationQueue: Sendable {
    public let pendingDirectory: URL
    private let now: @Sendable () -> Date

    public init(
        pendingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Hermes Touch Bar/meeting-todo-confirmations/pending", isDirectory: true),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.pendingDirectory = pendingDirectory
        self.now = now
    }

    public func pendingCandidates() -> [MeetingTodoCandidate] {
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(
            at: pendingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var candidates: [MeetingTodoCandidate] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                decoder.userInfo[.meetingTodoFileURL] = file
                let candidate = try decoder.decode(MeetingTodoCandidate.self, from: Data(contentsOf: file))
                if candidate.expiresAt <= now() {
                    try? manager.removeItem(at: file)
                } else {
                    candidates.append(candidate)
                }
            } catch {
                continue
            }
        }
        return candidates.sorted { $0.createdAt < $1.createdAt }
    }

    public func candidate(id: String) -> MeetingTodoCandidate? {
        pendingCandidates().first { $0.id == id }
    }

    public func discard(_ candidate: MeetingTodoCandidate) throws {
        try FileManager.default.removeItem(at: candidate.fileURL)
    }
}
