import Foundation

struct RolloutTaskEvent: Equatable, Sendable {
    let type: String
    let timestamp: Date?
}

struct RolloutTailUpdate: Equatable, Sendable {
    let latestEvent: RolloutTaskEvent?
    let latestShortTermLimit: WeeklyLimitUsage?
    let latestWeeklyLimit: WeeklyLimitUsage?
    let latestAssistantResult: String?
    let processedOffset: UInt64
    let bytesRead: Int
}

enum RolloutTailReader {
    static func readChanges(at url: URL, from offset: UInt64) throws -> RolloutTailUpdate {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        try handle.seek(toOffset: offset)
        let data = try handle.readToEnd() ?? Data()
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else {
            return RolloutTailUpdate(
                latestEvent: nil,
                latestShortTermLimit: nil,
                latestWeeklyLimit: nil,
                latestAssistantResult: nil,
                processedOffset: offset,
                bytesRead: data.count
            )
        }

        let completedData = data.prefix(through: lastNewline)
        var latestEvent: RolloutTaskEvent?
        var latestShortTermLimit: WeeklyLimitUsage?
        var latestWeeklyLimit: WeeklyLimitUsage?
        var latestAssistantResult: String?
        for line in completedData.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let events = lineEvents(in: Data(line))
            latestEvent = events.task ?? latestEvent
            latestShortTermLimit = events.shortTermLimit ?? latestShortTermLimit
            latestWeeklyLimit = events.weeklyLimit ?? latestWeeklyLimit
            latestAssistantResult = assistantResult(in: Data(line)) ?? latestAssistantResult
        }

        return RolloutTailUpdate(
            latestEvent: latestEvent,
            latestShortTermLimit: latestShortTermLimit,
            latestWeeklyLimit: latestWeeklyLimit,
            latestAssistantResult: latestAssistantResult,
            processedOffset: offset + UInt64(completedData.count),
            bytesRead: data.count
        )
    }

    static func endOfLastCompleteLine(at url: URL, fileSize: UInt64) throws -> UInt64 {
        guard fileSize > 0 else {
            return 0
        }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let chunkSize: UInt64 = 64 * 1_024
        var position = fileSize
        while position > 0 {
            let readStart = position > chunkSize ? position - chunkSize : 0
            try handle.seek(toOffset: readStart)
            let data = try handle.read(upToCount: Int(position - readStart)) ?? Data()
            if let newline = data.lastIndex(of: UInt8(ascii: "\n")) {
                return readStart + UInt64(newline + 1)
            }
            position = readStart
        }
        return 0
    }

    static func taskEvent(in lineData: Data) -> RolloutTaskEvent? {
        lineEvents(in: lineData).task
    }

    static func weeklyLimit(in lineData: Data) -> WeeklyLimitUsage? {
        lineEvents(in: lineData).weeklyLimit
    }

    static func assistantResult(in lineData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              let payload = envelope["payload"] as? [String: Any] else {
            return nil
        }
        let phase = payload["phase"] as? String
        guard phase == nil || phase == "final_answer" else { return nil }

        let rawText: String?
        if envelope["type"] as? String == "event_msg",
           payload["type"] as? String == "agent_message" {
            rawText = payload["message"] as? String
        } else if envelope["type"] as? String == "response_item",
                  payload["type"] as? String == "message",
                  payload["role"] as? String == "assistant",
                  let content = payload["content"] as? [[String: Any]] {
            rawText = content.compactMap { item in
                guard item["type"] as? String == "output_text" else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n")
        } else {
            rawText = nil
        }
        guard let rawText else { return nil }
        var displayText = rawText
        if let citationStart = displayText.range(of: "<oai-mem-citation>") {
            displayText.removeSubrange(citationStart.lowerBound...)
        }
        displayText = displayText.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^\)]+\)"#,
            with: "$1",
            options: .regularExpression
        )
        displayText = displayText.replacingOccurrences(
            of: #"[*_`#>]"#,
            with: "",
            options: .regularExpression
        )
        displayText = displayText.replacingOccurrences(
            of: #"(?:^|\s)[-•]\s+"#,
            with: " ",
            options: .regularExpression
        )
        let compact = displayText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !compact.isEmpty else { return nil }
        return compact.count > 120 ? String(compact.prefix(119)) + "…" : compact
    }

    static func lineEvents(
        in lineData: Data
    ) -> (task: RolloutTaskEvent?, shortTermLimit: WeeklyLimitUsage?, weeklyLimit: WeeklyLimitUsage?) {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "event_msg",
              let payload = envelope["payload"] as? [String: Any] else {
            return (nil, nil, nil)
        }

        let timestamp = parseTimestamp(envelope["timestamp"])
        let task: RolloutTaskEvent?
        if let eventType = payload["type"] as? String,
           ["task_started", "task_complete", "turn_aborted"].contains(eventType) {
            task = RolloutTaskEvent(type: eventType, timestamp: timestamp)
        } else {
            task = nil
        }

        guard payload["type"] as? String == "token_count",
              let rateLimits = payload["rate_limits"] as? [String: Any],
              let recordedAt = timestamp else {
            return (task, nil, nil)
        }

        let windows = ["primary", "secondary"]
            .compactMap { rateLimits[$0] as? [String: Any] }
        func usage(windowMinutes: Int) -> WeeklyLimitUsage? {
            guard let window = windows.first(where: {
                ($0["window_minutes"] as? NSNumber)?.intValue == windowMinutes
            }), let usedPercent = (window["used_percent"] as? NSNumber)?.doubleValue else {
                return nil
            }
            let resetsAt = (window["resets_at"] as? NSNumber)
                .map { Date(timeIntervalSince1970: $0.doubleValue) }
            return WeeklyLimitUsage(
                usedPercent: usedPercent,
                resetsAt: resetsAt,
                recordedAt: recordedAt
            )
        }
        return (
            task,
            usage(windowMinutes: 5 * 60),
            usage(windowMinutes: 7 * 24 * 60)
        )
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        guard let timestamp = value as? String else {
            return nil
        }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: timestamp) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: timestamp)
    }
}
