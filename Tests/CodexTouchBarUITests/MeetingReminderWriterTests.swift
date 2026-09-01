import Foundation
import Testing
@testable import CodexTouchBar

@MainActor @Test func meetingReminderDueDateAcceptsStableDateFormats() {
    #expect(MeetingReminderWriter.parseDueDate("2026-09-02") != nil)
    #expect(MeetingReminderWriter.parseDueDate("2026/9/2") != nil)
    #expect(MeetingReminderWriter.parseDueDate("待确认") == nil)
    #expect(MeetingReminderWriter.parseDueDate("下周") == nil)
}
