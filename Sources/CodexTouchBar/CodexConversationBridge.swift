import CodexTouchBarCore
import Foundation

struct CodexConversationResult: Sendable {
    let threadID: String
    let assistantText: String
    let steeredActiveTurn: Bool
}

struct CodexPrompt: Sendable {
    let text: String
    let imageURLs: [URL]

    var isEmpty: Bool { text.isEmpty && imageURLs.isEmpty }
}

enum CodexConversationRoute: Sendable {
    case desktopThread(threadID: String, cwd: URL, isActive: Bool)
    case appServerThread(threadID: String)
    case new(cwd: URL)
}

enum CodexConversationBridgeError: LocalizedError, Sendable {
    case executableUnavailable
    case serverStopped
    case invalidResponse(String)
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableUnavailable:
            "未找到 Codex 命令行程序。"
        case .serverStopped:
            "Codex App Server 已意外停止。"
        case let .invalidResponse(message):
            "Codex 返回了无效响应：\(message)"
        case let .requestFailed(message):
            "Codex 未接受指令：\(message)"
        }
    }
}

enum CodexConversationBridge {
    static func send(
        prompt: CodexPrompt,
        route: CodexConversationRoute
    ) async throws -> CodexConversationResult {
        if case let .desktopThread(threadID, cwd, isActive) = route {
            let disposition = try await CodexIPCClient().sendPrompt(
                threadID: threadID,
                cwd: cwd,
                prompt: prompt.text,
                imagePaths: prompt.imageURLs.map(\.path),
                isActive: isActive
            )
            return CodexConversationResult(
                threadID: threadID,
                assistantText: isActive ? "指令已追加到当前任务。" : "新一轮任务已开始。",
                steeredActiveTurn: disposition == .steeredActiveTurn
            )
        }
        return try await Task.detached(priority: .userInitiated) {
            try CodexAppServerInvocation.run(prompt: prompt, route: route)
        }.value
    }

    static func releaseWorkIslandOwnership(threadID: String) -> Bool {
        BackgroundTurnRegistry.shared.release(threadID: threadID)
    }
}

private final class BackgroundTurnRegistry: @unchecked Sendable {
    static let shared = BackgroundTurnRegistry()

    private struct Entry {
        let process: Process
        let writer: FileHandle
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func register(threadID: String, process: Process, writer: FileHandle) {
        lock.lock()
        entries[threadID] = Entry(process: process, writer: writer)
        lock.unlock()
    }

    func finish(threadID: String) {
        lock.lock()
        entries.removeValue(forKey: threadID)
        lock.unlock()
    }

    func release(threadID: String) -> Bool {
        lock.lock()
        let entry = entries.removeValue(forKey: threadID)
        lock.unlock()
        guard let entry else { return false }
        try? entry.writer.close()
        if entry.process.isRunning { entry.process.terminate() }
        return true
    }
}

private enum CodexAppServerInvocation {
    private static let initializeID = 1
    private static let threadID = 2
    private static let turnID = 3

    static func run(
        prompt: CodexPrompt,
        route: CodexConversationRoute
    ) throws -> CodexConversationResult {
        guard let executableURL = locateCodexExecutable() else {
            throw CodexConversationBridgeError.executableUnavailable
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        try process.run()

        let writer = inputPipe.fileHandleForWriting
        let reader = JSONLineReader(handle: outputPipe.fileHandleForReading)
        var handedOffToBackground = false
        defer {
            if !handedOffToBackground {
                try? writer.close()
                if process.isRunning { process.terminate() }
            }
        }

        try write([
            "method": "initialize",
            "id": initializeID,
            "params": [
                "clientInfo": [
                    "name": "codex-hermes-touch-bar",
                    "title": "AI 工作岛",
                    "version": "0.6.0",
                ],
            ],
        ], to: writer)
        _ = try waitForResponse(id: initializeID, reader: reader, process: process)
        try write(["method": "initialized", "params": [:]], to: writer)

        let resolvedThreadID: String
        let activeTurnID: String?
        switch route {
        case .desktopThread:
            throw CodexConversationBridgeError.invalidResponse("桌面会话应通过桌面端通道发送")
        case let .appServerThread(existingThreadID):
            try write([
                "method": "thread/resume",
                "id": threadID,
                "params": ["threadId": existingThreadID],
            ], to: writer)
            let response = try waitForResponse(id: threadID, reader: reader, process: process)
            guard let result = response["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let resumedThreadID = thread["id"] as? String else {
                throw CodexConversationBridgeError.invalidResponse("续接会话缺少 thread.id")
            }
            resolvedThreadID = resumedThreadID
            activeTurnID = activeTurnIdentifier(in: response)
        case let .new(cwd):
            try write([
                "method": "thread/start",
                "id": threadID,
                "params": [
                    "cwd": cwd.path,
                    "serviceName": "codex-desktop",
                    "threadSource": "vscode",
                    "ephemeral": false,
                ],
            ], to: writer)
            let response = try waitForResponse(id: threadID, reader: reader, process: process)
            guard let result = response["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let createdThreadID = thread["id"] as? String else {
                throw CodexConversationBridgeError.invalidResponse("新会话缺少 thread.id")
            }
            resolvedThreadID = createdThreadID
            activeTurnID = nil
        }

        if let activeTurnID {
            try write([
                "method": "turn/steer",
                "id": turnID,
                "params": [
                    "threadId": resolvedThreadID,
                    "expectedTurnId": activeTurnID,
                    "input": userInput(for: prompt),
                ],
            ], to: writer)
        } else {
            try write([
                "method": "turn/start",
                "id": turnID,
                "params": [
                    "threadId": resolvedThreadID,
                    "input": userInput(for: prompt),
                ],
            ], to: writer)
        }

        let turnResponse = try waitForResponse(id: turnID, reader: reader, process: process)
        let acceptedTurnID = responseTurnIdentifier(turnResponse) ?? activeTurnID
        if case .new = route {
            retainWorkIslandThread(resolvedThreadID)
            BackgroundTurnRegistry.shared.register(
                threadID: resolvedThreadID,
                process: process,
                writer: writer
            )
            handedOffToBackground = true
            drainAcceptedTurnInBackground(
                threadID: resolvedThreadID,
                turnID: acceptedTurnID,
                reader: reader,
                writer: writer,
                process: process,
                imageURLs: prompt.imageURLs
            )
            return CodexConversationResult(
                threadID: resolvedThreadID,
                assistantText: "会话已创建，任务正在执行。",
                steeredActiveTurn: false
            )
        }
        let assistantText = try readUntilTurnCompletes(
            threadID: resolvedThreadID,
            turnID: acceptedTurnID,
            reader: reader,
            process: process
        )
        return CodexConversationResult(
            threadID: resolvedThreadID,
            assistantText: assistantText.isEmpty ? "指令已完成。" : assistantText,
            steeredActiveTurn: activeTurnID != nil
        )
    }

    private static func drainAcceptedTurnInBackground(
        threadID: String,
        turnID: String?,
        reader: JSONLineReader,
        writer: FileHandle,
        process: Process,
        imageURLs: [URL]
    ) {
        DispatchQueue.global(qos: .utility).async {
            defer { BackgroundTurnRegistry.shared.finish(threadID: threadID) }
            _ = try? readUntilTurnCompletes(
                threadID: threadID,
                turnID: turnID,
                reader: reader,
                process: process
            )
            try? writer.close()
            if process.isRunning { process.terminate() }
            for url in imageURLs { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static func retainWorkIslandThread(_ threadID: String) {
        let fileManager = FileManager.default
        let directory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Hermes Touch Bar", isDirectory: true)
        let file = directory.appendingPathComponent("work-island-thread-ids.json")
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = (try? Data(contentsOf: file))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        let retained = Array(([threadID] + existing.filter { $0 != threadID }).prefix(100))
        guard let data = try? JSONEncoder().encode(retained) else { return }
        try? data.write(to: file, options: .atomic)
    }

    private static func userInput(for prompt: CodexPrompt) -> [[String: Any]] {
        var input: [[String: Any]] = []
        if !prompt.text.isEmpty {
            input.append(["type": "text", "text": prompt.text])
        }
        input.append(contentsOf: prompt.imageURLs.map {
            ["type": "localImage", "path": $0.path]
        })
        return input
    }

    private static func locateCodexExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func write(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func waitForResponse(
        id: Int,
        reader: JSONLineReader,
        process: Process
    ) throws -> [String: Any] {
        while process.isRunning {
            let message = try reader.nextObject()
            guard (message["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = message["error"] as? [String: Any] {
                let text = error["message"] as? String ?? String(describing: error)
                throw CodexConversationBridgeError.requestFailed(text)
            }
            return message
        }
        throw CodexConversationBridgeError.serverStopped
    }

    private static func activeTurnIdentifier(in response: [String: Any]) -> String? {
        guard let result = response["result"] as? [String: Any],
              let thread = result["thread"] as? [String: Any],
              let turns = thread["turns"] as? [[String: Any]] else { return nil }
        return turns.reversed().first(where: {
            ($0["status"] as? String) == "inProgress"
        })?["id"] as? String
    }

    private static func responseTurnIdentifier(_ response: [String: Any]) -> String? {
        guard let result = response["result"] as? [String: Any] else { return nil }
        if let turn = result["turn"] as? [String: Any] {
            return turn["id"] as? String
        }
        return result["turnId"] as? String
    }

    private static func readUntilTurnCompletes(
        threadID: String,
        turnID: String?,
        reader: JSONLineReader,
        process: Process
    ) throws -> String {
        var assistantText = ""
        while process.isRunning {
            let message = try reader.nextObject()
            let method = message["method"] as? String
            let params = message["params"] as? [String: Any]
            if method == "item/agentMessage/delta",
               let delta = params?["delta"] as? String {
                assistantText += delta
            }
            if method == "turn/completed",
               let turn = params?["turn"] as? [String: Any],
               (turn["id"] as? String) == turnID || turnID == nil,
               (params?["threadId"] as? String) == threadID {
                return assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        throw CodexConversationBridgeError.serverStopped
    }
}

private final class JSONLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func nextObject() throws -> [String: Any] {
        while true {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newlineIndex]
                buffer.removeSubrange(...newlineIndex)
                guard !line.isEmpty else { continue }
                guard let object = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                    throw CodexConversationBridgeError.invalidResponse("无法解析 JSON 行")
                }
                return object
            }
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                throw CodexConversationBridgeError.serverStopped
            }
            buffer.append(chunk)
        }
    }
}
