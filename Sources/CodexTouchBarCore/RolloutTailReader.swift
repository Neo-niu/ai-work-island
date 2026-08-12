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
    let liveActivities: [String]
    let latestPlanProgress: CodexLiveProgress?
    let resetsLiveProgress: Bool
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
                liveActivities: [],
                latestPlanProgress: nil,
                resetsLiveProgress: false,
                processedOffset: offset,
                bytesRead: data.count
            )
        }

        let completedData = data.prefix(through: lastNewline)
        var latestEvent: RolloutTaskEvent?
        var latestShortTermLimit: WeeklyLimitUsage?
        var latestWeeklyLimit: WeeklyLimitUsage?
        var latestAssistantResult: String?
        var liveActivities: [String] = []
        var latestPlanProgress: CodexLiveProgress?
        var resetsLiveProgress = false
        for line in completedData.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            let lineData = Data(line)
            let events = lineEvents(in: lineData)
            if events.task?.type == "task_started" {
                liveActivities.removeAll(keepingCapacity: true)
                latestPlanProgress = nil
                resetsLiveProgress = true
            }
            latestEvent = events.task ?? latestEvent
            latestShortTermLimit = events.shortTermLimit ?? latestShortTermLimit
            latestWeeklyLimit = events.weeklyLimit ?? latestWeeklyLimit
            latestAssistantResult = assistantResult(in: lineData) ?? latestAssistantResult
            if let activity = activityMessage(in: lineData), liveActivities.last != activity {
                liveActivities.append(activity)
                liveActivities = Array(liveActivities.suffix(3))
            }
            latestPlanProgress = planProgress(in: lineData) ?? latestPlanProgress
        }

        return RolloutTailUpdate(
            latestEvent: latestEvent,
            latestShortTermLimit: latestShortTermLimit,
            latestWeeklyLimit: latestWeeklyLimit,
            latestAssistantResult: latestAssistantResult,
            liveActivities: liveActivities,
            latestPlanProgress: latestPlanProgress,
            resetsLiveProgress: resetsLiveProgress,
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
        return compactDisplayText(rawText)
    }

    static func activityMessage(in lineData: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              let payload = envelope["payload"] as? [String: Any] else {
            return nil
        }

        let rawText: String?
        if envelope["type"] as? String == "event_msg",
           payload["type"] as? String == "agent_message",
           payload["phase"] as? String == "commentary" {
            rawText = payload["message"] as? String
        } else if envelope["type"] as? String == "response_item",
                  payload["type"] as? String == "message",
                  payload["role"] as? String == "assistant",
                  payload["phase"] as? String == "commentary",
                  let content = payload["content"] as? [[String: Any]] {
            rawText = content.compactMap { item in
                guard item["type"] as? String == "output_text" else { return nil }
                return item["text"] as? String
            }.joined(separator: "\n")
        } else if envelope["type"] as? String == "response_item",
                  payload["type"] as? String == "custom_tool_call",
                  let name = payload["name"] as? String {
            rawText = toolActivity(name: name)
        } else {
            rawText = nil
        }
        guard let rawText else { return nil }
        return compactDisplayText(rawText)
    }

    static func planProgress(in lineData: Data) -> CodexLiveProgress? {
        guard let object = try? JSONSerialization.jsonObject(with: lineData),
              let envelope = object as? [String: Any],
              envelope["type"] as? String == "response_item",
              let payload = envelope["payload"] as? [String: Any] else {
            return nil
        }

        let plan: [[String: Any]]
        if payload["type"] as? String == "function_call",
           payload["name"] as? String == "update_plan",
           let arguments = payload["arguments"] as? String,
           let argumentsData = arguments.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: argumentsData) as? [String: Any],
           let parsedPlan = root["plan"] as? [[String: Any]] {
            plan = parsedPlan
        } else if payload["type"] as? String == "custom_tool_call",
                  payload["name"] as? String == "exec",
                  let input = payload["input"] as? String {
            plan = planSteps(inExecInput: input)
        } else {
            return nil
        }
        guard !plan.isEmpty else { return nil }
        let completed = plan.filter { $0["status"] as? String == "completed" }.count
        let currentStep = plan.first { $0["status"] as? String == "in_progress" }?["step"] as? String
        let activities = currentStep.flatMap(compactDisplayText).map { [$0] } ?? []
        return CodexLiveProgress(
            activities: activities,
            completedStepCount: completed,
            totalStepCount: plan.count
        )
    }

    private static func planSteps(inExecInput input: String) -> [[String: Any]] {
        guard input.contains("tools.update_plan(") else { return [] }
        let pattern = #"step\s*:\s*\"((?:\\.|[^\"\\])*)\"\s*,\s*status\s*:\s*\"(completed|in_progress|pending)\""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).compactMap { match in
            guard let stepRange = Range(match.range(at: 1), in: input),
                  let statusRange = Range(match.range(at: 2), in: input) else {
                return nil
            }
            let escapedStep = String(input[stepRange])
            let step: String
            if let data = "\"\(escapedStep)\"".data(using: .utf8),
               let decoded = try? JSONDecoder().decode(String.self, from: data) {
                step = decoded
            } else {
                step = escapedStep
            }
            return ["step": step, "status": String(input[statusRange])]
        }
    }

    private static func toolActivity(name: String) -> String? {
        switch name {
        case "exec_command": "正在运行命令"
        case "apply_patch": "正在修改文件"
        case "web__run", "web_search": "正在查询资料"
        case "view_image": "正在检查图片"
        case "write_stdin": "正在等待命令结果"
        default: nil
        }
    }

    private static func compactDisplayText(_ rawText: String) -> String? {
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
