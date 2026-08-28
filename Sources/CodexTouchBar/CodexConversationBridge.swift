import CodexTouchBarCore
import Darwin
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

enum CodexCardContinuationPolicy {
    static func route(threadID: String, cwd: URL, isActive: Bool) -> CodexConversationRoute {
        .desktopThread(threadID: threadID, cwd: cwd, isActive: isActive)
    }
}

struct CodexQueueCommand: Equatable {
    let executableURL: URL
    let arguments: [String]

    static func make(
        executableURL: URL,
        threadID: String,
        prompt: CodexPrompt,
        cwd: URL
    ) -> CodexQueueCommand {
        let message = CodexQueuedImageFallback.message(
            text: prompt.text,
            imageURLs: prompt.imageURLs
        )
        let arguments = [
            "queue",
            "--thread", threadID,
            "--message", message,
            "-C", cwd.path,
        ]
        return CodexQueueCommand(executableURL: executableURL, arguments: arguments)
    }
}

enum CodexOwnershipReleaseResult: Equatable {
    case released
    case alreadyTransferred
    case failed(String)
}

enum ThreadOwnershipState: Equatable {
    case workIsland
    case transferring
    case codex
}

struct ThreadOwnershipStateMachine {
    private(set) var state: ThreadOwnershipState = .workIsland

    mutating func beginTransfer() -> Bool {
        guard state == .workIsland else { return false }
        state = .transferring
        return true
    }

    mutating func confirmTransfer() -> Bool {
        guard state == .transferring else { return false }
        state = .codex
        return true
    }

    mutating func rollbackTransfer() -> Bool {
        guard state == .transferring else { return false }
        state = .workIsland
        return true
    }
}

enum SharedAppServerLifetimePolicy {
    static func shouldStop(workIslandOwnedThreadCount: Int) -> Bool {
        workIslandOwnedThreadCount == 0
    }
}

enum RestartRecoveryTransferPolicy {
    static func shouldWaitForPeerTasks(
        hasInProcessOwner: Bool,
        hasOtherActiveWorkIslandThread: Bool
    ) -> Bool {
        !hasInProcessOwner && hasOtherActiveWorkIslandThread
    }

    static func canStopServerBeforeOpening(
        hasInProcessOwner: Bool,
        hasOtherActiveWorkIslandThread: Bool
    ) -> Bool {
        !hasInProcessOwner && !hasOtherActiveWorkIslandThread
    }
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

enum DurableCodexAppServer {
    static let launchLabel = "dev.kanyun.AIWorkIsland.CodexAppServer"

    static var socketURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Codex Hermes Touch Bar/codex-app-server",
                isDirectory: true
            )
            .appendingPathComponent("app-server.sock")
    }

    static func launchctlSubmitArguments(executableURL: URL, socketURL: URL) -> [String] {
        let logURL = socketURL.deletingLastPathComponent().appendingPathComponent("app-server.log")
        return [
            "submit",
            "-l", launchLabel,
            "-o", logURL.path,
            "-e", logURL.path,
            "--",
            executableURL.path,
            "app-server",
            "--listen", "unix://\(socketURL.path)",
        ]
    }

    static func ensureRunning(executableURL: URL) throws -> URL {
        try lock.withLock {
            let socketURL = socketURL
            let directoryURL = socketURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            if isLaunchJobLoaded(), waitForSocket(socketURL, attempts: 10) {
                return socketURL
            }

            removeLaunchJob()
            try? FileManager.default.removeItem(at: socketURL)

            let submit = Process()
            submit.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            submit.arguments = launchctlSubmitArguments(
                executableURL: executableURL,
                socketURL: socketURL
            )
            submit.standardOutput = FileHandle.nullDevice
            submit.standardError = FileHandle.nullDevice
            try submit.run()
            submit.waitUntilExit()
            guard submit.terminationStatus == 0 else {
                throw CodexConversationBridgeError.requestFailed("无法启动独立 Codex 任务服务")
            }
            guard waitForSocket(socketURL, attempts: 60) else {
                removeLaunchJob()
                throw CodexConversationBridgeError.requestFailed("独立 Codex 任务服务启动超时")
            }
            return socketURL
        }
    }

    static func stop() {
        lock.withLock {
            removeLaunchJob()
            try? FileManager.default.removeItem(at: socketURL)
        }
    }

    private static let lock = NSLock()

    private static func isLaunchJobLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", launchLabel]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func removeLaunchJob() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["remove", launchLabel]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    private static func waitForSocket(_ socketURL: URL, attempts: Int) -> Bool {
        for _ in 0..<attempts {
            if FileManager.default.fileExists(atPath: socketURL.path) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}

enum CodexConversationBridge {
    static func newThreadStartParams(cwd: URL) -> [String: Any] {
        [
            "cwd": cwd.path,
            "serviceName": "codex-desktop",
            "threadSource": "vscode",
            "ephemeral": false,
            "approvalPolicy": "never",
            "sandbox": "danger-full-access",
        ]
    }

    static func turnStartParams(threadID: String, prompt: CodexPrompt) -> [String: Any] {
        [
            "threadId": threadID,
            "input": userInput(for: prompt),
            // Repeat the sticky permission settings on the first turn. Recent
            // App Server builds can apply a host permission profile after
            // thread/start; turn/start is the authoritative persisted override.
            "approvalPolicy": "never",
            "sandboxPolicy": ["type": "dangerFullAccess"],
        ]
    }

    static func threadUnsubscribeRequest(threadID: String, id: Int = 4) -> [String: Any] {
        [
            "method": "thread/unsubscribe",
            "id": id,
            "params": ["threadId": threadID],
        ]
    }

    static func userInput(for prompt: CodexPrompt) -> [[String: Any]] {
        var input: [[String: Any]] = []
        if !prompt.text.isEmpty {
            input.append(["type": "text", "text": prompt.text])
        }
        input.append(contentsOf: prompt.imageURLs.map {
            ["type": "localImage", "path": $0.path]
        })
        return input
    }

    static func send(
        prompt: CodexPrompt,
        route: CodexConversationRoute
    ) async throws -> CodexConversationResult {
        if case let .desktopThread(threadID, cwd, isActive) = route {
            return try await Task.detached(priority: .userInitiated) {
                try CodexQueueInvocation.run(
                    threadID: threadID,
                    prompt: prompt,
                    cwd: cwd,
                    isActive: isActive
                )
            }.value
        }
        return try await Task.detached(priority: .userInitiated) {
            try CodexAppServerInvocation.run(prompt: prompt, route: route)
        }.value
    }

    static func releaseWorkIslandOwnership(
        threadID: String,
        timeout: TimeInterval = 5
    ) async -> CodexOwnershipReleaseResult {
        await Task.detached(priority: .userInitiated) {
            if !BackgroundTurnRegistry.shared.contains(threadID: threadID) {
                return CodexAppServerInvocation.unsubscribeDetached(
                    threadID: threadID,
                    timeout: timeout
                )
            }
            return BackgroundTurnRegistry.shared.release(threadID: threadID, timeout: timeout)
        }.value
    }

    static func ownershipState(threadID: String) -> ThreadOwnershipState {
        BackgroundTurnRegistry.shared.ownershipState(threadID: threadID)
    }

    static func hasInProcessOwner(threadID: String) -> Bool {
        BackgroundTurnRegistry.shared.contains(threadID: threadID)
    }
}

private enum CodexQueueInvocation {
    static func run(
        threadID: String,
        prompt: CodexPrompt,
        cwd: URL,
        isActive: Bool
    ) throws -> CodexConversationResult {
        guard let executableURL = CodexAppServerInvocation.locateCodexExecutable() else {
            throw CodexConversationBridgeError.executableUnavailable
        }
        let stagedImages = try CodexQueuedImageFallback.stage(prompt.imageURLs)
        let queuedPrompt = CodexPrompt(text: prompt.text, imageURLs: stagedImages)
        let command = CodexQueueCommand.make(
            executableURL: executableURL,
            threadID: threadID,
            prompt: queuedPrompt,
            cwd: cwd
        )
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let outputText = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        let errorText = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        guard process.terminationStatus == 0 else {
            let detail = [errorText, outputText]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? "Codex Queue 未接受这条消息。"
            throw CodexConversationBridgeError.requestFailed(detail)
        }
        return CodexConversationResult(
            threadID: threadID,
            assistantText: isActive ? "指令已排队，将在当前任务后继续。" : "新一轮任务已交给 Codex。",
            steeredActiveTurn: false
        )
    }
}

private final class BackgroundTurnRegistry: @unchecked Sendable {
    static let shared = BackgroundTurnRegistry()

    private struct Entry {
        let connection: UnixWebSocketJSONConnection
        var ownership = ThreadOwnershipStateMachine()
        var transferSignal: DispatchSemaphore?
        var transferError: String?
        var rollbackRequested = false
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var activeInvocations = 0

    func beginInvocation() {
        lock.lock()
        activeInvocations += 1
        lock.unlock()
    }

    @discardableResult
    func endInvocation() -> Bool {
        lock.lock()
        activeInvocations = max(0, activeInvocations - 1)
        let idle = entries.isEmpty && activeInvocations == 0
        lock.unlock()
        return idle
    }

    func register(threadID: String, connection: UnixWebSocketJSONConnection) {
        lock.lock()
        entries[threadID] = Entry(connection: connection)
        lock.unlock()
    }

    @discardableResult
    func finish(threadID: String) -> Bool {
        lock.lock()
        entries.removeValue(forKey: threadID)
        let idle = entries.isEmpty && activeInvocations == 0
        lock.unlock()
        return idle
    }

    var isIdle: Bool {
        lock.lock()
        let idle = entries.isEmpty && activeInvocations == 0
        lock.unlock()
        return idle
    }

    func ownershipState(threadID: String) -> ThreadOwnershipState {
        lock.lock()
        let state = entries[threadID]?.ownership.state ?? .codex
        lock.unlock()
        return state
    }

    func contains(threadID: String) -> Bool {
        lock.lock()
        let contains = entries[threadID] != nil
        lock.unlock()
        return contains
    }

    func release(threadID: String, timeout: TimeInterval) -> CodexOwnershipReleaseResult {
        let signal = DispatchSemaphore(value: 0)
        lock.lock()
        guard var entry = entries[threadID] else {
            lock.unlock()
            return .alreadyTransferred
        }
        guard entry.ownership.beginTransfer() else {
            let state = entry.ownership.state
            lock.unlock()
            return state == .codex ? .alreadyTransferred : .failed("该任务正在转移，请勿重复操作")
        }
        entry.transferSignal = signal
        entry.transferError = nil
        entry.rollbackRequested = false
        entries[threadID] = entry
        lock.unlock()

        do {
            try entry.connection.send(
                CodexConversationBridge.threadUnsubscribeRequest(threadID: threadID)
            )
        } catch {
            rollback(threadID: threadID)
            return .failed("退订请求发送失败：\(error.localizedDescription)")
        }
        guard signal.wait(timeout: .now() + timeout) == .success else {
            let recoverySignal = DispatchSemaphore(value: 0)
            lock.lock()
            if var recoveringEntry = entries[threadID] {
                recoveringEntry.rollbackRequested = true
                recoveringEntry.transferSignal = recoverySignal
                entries[threadID] = recoveringEntry
            }
            lock.unlock()
            do {
                try entry.connection.send([
                    "method": "thread/resume",
                    "id": 5,
                    "params": ["threadId": threadID],
                ])
            } catch {
                rollback(threadID: threadID)
                return .failed("转移超时，恢复订阅失败：\(error.localizedDescription)")
            }
            guard recoverySignal.wait(timeout: .now() + timeout) == .success else {
                rollback(threadID: threadID)
                return .failed("转移超时，无法确认工作岛已恢复所有权")
            }
            return .failed("转移超时，工作岛已恢复该线程所有权")
        }
        lock.lock()
        let result: CodexOwnershipReleaseResult
        if let error = entries[threadID]?.transferError {
            if var failedEntry = entries[threadID] {
                _ = failedEntry.ownership.rollbackTransfer()
                failedEntry.transferSignal = nil
                entries[threadID] = failedEntry
            }
            result = .failed(error)
        } else if var confirmedEntry = entries.removeValue(forKey: threadID) {
            _ = confirmedEntry.ownership.confirmTransfer()
            confirmedEntry.connection.close()
            result = .released
        } else {
            result = .alreadyTransferred
        }
        let idle = entries.isEmpty && activeInvocations == 0
        lock.unlock()
        if SharedAppServerLifetimePolicy.shouldStop(
            workIslandOwnedThreadCount: idle ? 0 : 1
        ) {
            DurableCodexAppServer.stop()
        }
        return result
    }


    func consumeTransferResponse(threadID: String, message: [String: Any]) -> Bool {
        guard let responseID = (message["id"] as? NSNumber)?.intValue,
              responseID == 4 || responseID == 5 else { return false }
        lock.lock()
        guard var entry = entries[threadID], entry.ownership.state == .transferring else {
            lock.unlock()
            return false
        }
        if responseID == 4, entry.rollbackRequested {
            entries[threadID] = entry
            lock.unlock()
            return true
        }
        if let error = message["error"] as? [String: Any] {
            entry.transferError = error["message"] as? String ?? "Codex 拒绝退订该线程"
        }
        if responseID == 5 {
            _ = entry.ownership.rollbackTransfer()
            entry.rollbackRequested = false
        }
        let signal = entry.transferSignal
        entries[threadID] = entry
        lock.unlock()
        signal?.signal()
        return responseID == 4 && entry.transferError == nil
    }

    private func rollback(threadID: String) {
        lock.lock()
        if var entry = entries[threadID] {
            _ = entry.ownership.rollbackTransfer()
            entry.transferSignal = nil
            entry.transferError = nil
            entry.rollbackRequested = false
            entries[threadID] = entry
        }
        lock.unlock()
    }
}

private enum CodexAppServerInvocation {
    private static let initializeID = 1
    private static let threadID = 2
    private static let turnID = 3
    private static let unsubscribeID = 4

    static func unsubscribeDetached(
        threadID: String,
        timeout: TimeInterval
    ) -> CodexOwnershipReleaseResult {
        guard FileManager.default.fileExists(atPath: DurableCodexAppServer.socketURL.path) else {
            return .alreadyTransferred
        }
        do {
            let connection = try UnixWebSocketJSONConnection.connect(
                to: DurableCodexAppServer.socketURL,
                timeout: timeout
            )
            defer { connection.close() }
            try connection.send([
                "method": "initialize",
                "id": initializeID,
                "params": [
                    "clientInfo": [
                        "name": "codex-hermes-touch-bar-recovery",
                        "title": "AI工作岛恢复",
                        "version": "0.6.0",
                    ],
                ],
            ])
            _ = try waitForResponse(id: initializeID, connection: connection)
            try connection.send(["method": "initialized", "params": [:]])
            try connection.send(
                CodexConversationBridge.threadUnsubscribeRequest(
                    threadID: threadID,
                    id: unsubscribeID
                )
            )
            _ = try waitForResponse(id: unsubscribeID, connection: connection)
            return .released
        } catch {
            return .failed("重启后恢复转移失败：\(error.localizedDescription)")
        }
    }

    static func run(
        prompt: CodexPrompt,
        route: CodexConversationRoute
    ) throws -> CodexConversationResult {
        BackgroundTurnRegistry.shared.beginInvocation()
        defer {
            if BackgroundTurnRegistry.shared.endInvocation() {
                DurableCodexAppServer.stop()
            }
        }
        guard let executableURL = locateCodexExecutable() else {
            throw CodexConversationBridgeError.executableUnavailable
        }
        let socketURL = try DurableCodexAppServer.ensureRunning(executableURL: executableURL)

        let connection = try UnixWebSocketJSONConnection.connect(to: socketURL)
        var handedOffToBackground = false
        defer {
            if !handedOffToBackground {
                connection.close()
            }
        }

        try connection.send([
            "method": "initialize",
            "id": initializeID,
            "params": [
                "clientInfo": [
                    "name": "codex-hermes-touch-bar",
                    "title": "AI工作岛",
                    "version": "0.6.0",
                ],
            ],
        ])
        _ = try waitForResponse(id: initializeID, connection: connection)
        try connection.send(["method": "initialized", "params": [:]])

        let resolvedThreadID: String
        let activeTurnID: String?
        switch route {
        case .desktopThread:
            throw CodexConversationBridgeError.invalidResponse("桌面会话应通过桌面端通道发送")
        case let .appServerThread(existingThreadID):
            try connection.send([
                "method": "thread/resume",
                "id": threadID,
                "params": ["threadId": existingThreadID],
            ])
            let response = try waitForResponse(id: threadID, connection: connection)
            guard let result = response["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let resumedThreadID = thread["id"] as? String else {
                throw CodexConversationBridgeError.invalidResponse("续接会话缺少 thread.id")
            }
            resolvedThreadID = resumedThreadID
            activeTurnID = activeTurnIdentifier(in: response)
        case let .new(cwd):
            try connection.send([
                "method": "thread/start",
                "id": threadID,
                "params": CodexConversationBridge.newThreadStartParams(cwd: cwd),
            ])
            let response = try waitForResponse(id: threadID, connection: connection)
            guard let result = response["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let createdThreadID = thread["id"] as? String else {
                throw CodexConversationBridgeError.invalidResponse("新会话缺少 thread.id")
            }
            resolvedThreadID = createdThreadID
            activeTurnID = nil
        }

        if let activeTurnID {
            try connection.send([
                "method": "turn/steer",
                "id": turnID,
                "params": [
                    "threadId": resolvedThreadID,
                    "expectedTurnId": activeTurnID,
                    "input": CodexConversationBridge.userInput(for: prompt),
                ],
            ])
        } else {
            try connection.send([
                "method": "turn/start",
                "id": turnID,
                "params": CodexConversationBridge.turnStartParams(
                    threadID: resolvedThreadID,
                    prompt: prompt
                ),
            ])
        }

        let turnResponse = try waitForResponse(id: turnID, connection: connection)
        let acceptedTurnID = responseTurnIdentifier(turnResponse) ?? activeTurnID
        if case .new = route {
            retainWorkIslandThread(resolvedThreadID)
        }
        if case .new = route {
            BackgroundTurnRegistry.shared.register(
                threadID: resolvedThreadID,
                connection: connection
            )
            handedOffToBackground = true
            drainAcceptedTurnInBackground(
                threadID: resolvedThreadID,
                turnID: acceptedTurnID,
                connection: connection,
                imageURLs: prompt.imageURLs
            )
            return CodexConversationResult(
                threadID: resolvedThreadID,
                assistantText: "会话已创建，任务正在执行。",
                steeredActiveTurn: false
            )
        }
        if case .appServerThread = route {
            BackgroundTurnRegistry.shared.register(
                threadID: resolvedThreadID,
                connection: connection
            )
            handedOffToBackground = true
            drainAcceptedTurnInBackground(
                threadID: resolvedThreadID,
                turnID: acceptedTurnID,
                connection: connection,
                imageURLs: prompt.imageURLs
            )
            return CodexConversationResult(
                threadID: resolvedThreadID,
                assistantText: activeTurnID == nil ? "新一轮任务已开始。" : "指令已追加到当前任务。",
                steeredActiveTurn: activeTurnID != nil
            )
        }
        let assistantText = try readUntilTurnCompletes(
            threadID: resolvedThreadID,
            turnID: acceptedTurnID,
            connection: connection
        )
        try connection.send(
            CodexConversationBridge.threadUnsubscribeRequest(
                threadID: resolvedThreadID,
                id: unsubscribeID
            )
        )
        _ = try waitForResponse(id: unsubscribeID, connection: connection)
        return CodexConversationResult(
            threadID: resolvedThreadID,
            assistantText: assistantText.isEmpty ? "指令已完成。" : assistantText,
            steeredActiveTurn: activeTurnID != nil
        )
    }

    private static func drainAcceptedTurnInBackground(
        threadID: String,
        turnID: String?,
        connection: UnixWebSocketJSONConnection,
        imageURLs: [URL]
    ) {
        DispatchQueue.global(qos: .utility).async {
            defer {
                let becameIdle = BackgroundTurnRegistry.shared.finish(threadID: threadID)
                connection.close()
                for url in imageURLs { try? FileManager.default.removeItem(at: url) }
                if becameIdle {
                    DurableCodexAppServer.stop()
                }
            }
            do {
                _ = try readUntilTurnCompletes(
                    threadID: threadID,
                    turnID: turnID,
                    connection: connection
                )
                try connection.send(
                    CodexConversationBridge.threadUnsubscribeRequest(
                        threadID: threadID,
                        id: unsubscribeID
                    )
                )
                _ = try waitForResponse(id: unsubscribeID, connection: connection)
            } catch {
                // A manual transfer closes this connection after sending the same
                // unsubscribe request. The turn remains owned by the durable server
                // and Codex can subscribe to it from the desktop app.
            }
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

    fileprivate static func locateCodexExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            home.appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func waitForResponse(
        id: Int,
        connection: UnixWebSocketJSONConnection
    ) throws -> [String: Any] {
        while true {
            let message = try connection.nextObject()
            guard (message["id"] as? NSNumber)?.intValue == id else { continue }
            if let error = message["error"] as? [String: Any] {
                let text = error["message"] as? String ?? String(describing: error)
                throw CodexConversationBridgeError.requestFailed(text)
            }
            return message
        }
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
        connection: UnixWebSocketJSONConnection
    ) throws -> String {
        var assistantText = ""
        while true {
            let message = try connection.nextObject()
            if BackgroundTurnRegistry.shared.consumeTransferResponse(
                threadID: threadID,
                message: message
            ) {
                throw CodexConversationBridgeError.requestFailed("线程所有权已转交 Codex")
            }
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
    }
}

private final class UnixWebSocketJSONConnection: @unchecked Sendable {
    private let handle: FileHandle
    private var fragmentedPayload = Data()
    private let writeLock = NSLock()

    private init(handle: FileHandle) {
        self.handle = handle
    }

    static func connect(
        to socketURL: URL,
        timeout: TimeInterval? = nil
    ) throws -> UnixWebSocketJSONConnection {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw CodexConversationBridgeError.requestFailed("无法创建本地任务连接")
        }
        if let timeout {
            var value = timeval(
                tv_sec: Int(timeout),
                tv_usec: Int32((timeout - floor(timeout)) * 1_000_000)
            )
            withUnsafePointer(to: &value) { pointer in
                _ = setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    pointer,
                    socklen_t(MemoryLayout<timeval>.size)
                )
            }
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketURL.path.utf8)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        guard pathBytes.count < pathCapacity else {
            Darwin.close(descriptor)
            throw CodexConversationBridgeError.requestFailed("本地任务 Socket 路径过长")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }

        let pathOffset = MemoryLayout<sockaddr_un>.offset(of: \sockaddr_un.sun_path) ?? 0
        let addressLength = socklen_t(pathOffset + pathBytes.count + 1)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, addressLength)
            }
        }
        guard result == 0 else {
            Darwin.close(descriptor)
            throw CodexConversationBridgeError.requestFailed("无法连接独立 Codex 任务服务")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let connection = UnixWebSocketJSONConnection(handle: handle)
        try connection.performHandshake()
        return connection
    }

    func send(_ object: [String: Any]) throws {
        let payload = try JSONSerialization.data(withJSONObject: object)
        try sendFrame(opcode: 0x1, payload: payload)
    }

    func nextObject() throws -> [String: Any] {
        while true {
            let frame = try readFrame()
            switch frame.opcode {
            case 0x0:
                fragmentedPayload.append(frame.payload)
                if frame.isFinal { return try decode(fragmentedPayload, clearingFragment: true) }
            case 0x1:
                if frame.isFinal { return try decode(frame.payload, clearingFragment: false) }
                fragmentedPayload = frame.payload
            case 0x8:
                throw CodexConversationBridgeError.serverStopped
            case 0x9:
                try sendFrame(opcode: 0xA, payload: frame.payload)
            default:
                continue
            }
        }
    }

    func close() {
        try? handle.close()
    }

    private func performHandshake() throws {
        let key = Data((0..<16).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let request = """
        GET / HTTP/1.1\r
        Host: localhost\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Key: \(key)\r
        Sec-WebSocket-Version: 13\r
        \r

        """
        try handle.write(contentsOf: Data(request.utf8))
        var response = Data()
        let terminator = Data("\r\n\r\n".utf8)
        while response.suffix(terminator.count) != terminator && response.count < 16_384 {
            response.append(try readExactly(1))
        }
        guard let header = String(data: response, encoding: .utf8),
              header.hasPrefix("HTTP/1.1 101") else {
            throw CodexConversationBridgeError.requestFailed("独立 Codex 任务服务握手失败")
        }
    }

    private func sendFrame(opcode: UInt8, payload: Data) throws {
        writeLock.lock()
        defer { writeLock.unlock() }

        var frame = Data([0x80 | opcode])
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else if payload.count <= Int(UInt16.max) {
            frame.append(0x80 | 126)
            var length = UInt16(payload.count).bigEndian
            frame.append(Data(bytes: &length, count: 2))
        } else {
            frame.append(0x80 | 127)
            var length = UInt64(payload.count).bigEndian
            frame.append(Data(bytes: &length, count: 8))
        }
        let mask = (0..<4).map { _ in UInt8.random(in: 0...255) }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { index, byte in
            byte ^ mask[index % 4]
        })
        try handle.write(contentsOf: frame)
    }

    private func readFrame() throws -> (isFinal: Bool, opcode: UInt8, payload: Data) {
        let header = try readExactly(2)
        let first = header[header.startIndex]
        let second = header[header.index(after: header.startIndex)]
        let isFinal = (first & 0x80) != 0
        let opcode = first & 0x0F
        let isMasked = (second & 0x80) != 0
        var payloadLength = UInt64(second & 0x7F)
        if payloadLength == 126 {
            payloadLength = try readExactly(2).reduce(0) { ($0 << 8) | UInt64($1) }
        } else if payloadLength == 127 {
            payloadLength = try readExactly(8).reduce(0) { ($0 << 8) | UInt64($1) }
        }
        guard payloadLength <= UInt64(Int.max) else {
            throw CodexConversationBridgeError.invalidResponse("WebSocket 消息过大")
        }
        let mask = isMasked ? Array(try readExactly(4)) : []
        var payload = try readExactly(Int(payloadLength))
        if isMasked {
            payload = Data(payload.enumerated().map { index, byte in
                byte ^ mask[index % 4]
            })
        }
        return (isFinal, opcode, payload)
    }

    private func readExactly(_ count: Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let chunk = try handle.read(upToCount: count - data.count), !chunk.isEmpty else {
                throw CodexConversationBridgeError.serverStopped
            }
            data.append(chunk)
        }
        return data
    }

    private func decode(_ payload: Data, clearingFragment: Bool) throws -> [String: Any] {
        defer { if clearingFragment { fragmentedPayload.removeAll(keepingCapacity: true) } }
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw CodexConversationBridgeError.invalidResponse("无法解析 WebSocket 消息")
        }
        return object
    }
}
