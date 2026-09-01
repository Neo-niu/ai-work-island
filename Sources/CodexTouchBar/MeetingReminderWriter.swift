import EventKit
import Foundation
import CodexTouchBarCore

@MainActor
final class MeetingReminderWriter {
    enum WriterError: LocalizedError {
        case permissionDenied
        case noReminderList

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "没有提醒事项权限"
            case .noReminderList: "找不到可写入的提醒事项列表"
            }
        }
    }

    private let store = EKEventStore()

    func save(_ candidate: MeetingTodoCandidate) async throws {
        guard try await requestAccess() else { throw WriterError.permissionDenied }
        guard let calendar = store.defaultCalendarForNewReminders() else { throw WriterError.noReminderList }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = candidate.title
        reminder.notes = "来源会议：\(candidate.meetingTitle)（\(candidate.meetingDate)）\nObsidian：\(candidate.notePath)"
        if let due = Self.parseDueDate(candidate.dueDate) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
        }
        try store.save(reminder, commit: true)
    }

    private func requestAccess() async throws -> Bool {
        if #available(macOS 14.0, *) {
            return try await store.requestFullAccessToReminders()
        }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(to: .reminder) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    static func parseDueDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "待确认" else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        for format in ["yyyy-MM-dd", "yyyy/M/d", "M月d日"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }
}
