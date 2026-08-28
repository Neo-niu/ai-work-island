import Darwin
import Foundation

public actor CodexIPCClient {
    public enum PromptDisposition: Sendable {
        case startedTurn
        case steeredActiveTurn
    }

    public enum ClientError: LocalizedError {
        case socketUnavailable
        case connectionFailed(String)
        case invalidResponse
        case requestFailed(String)

        public var errorDescription: String? {
            switch self {
            case .socketUnavailable:
                "Codex 本机通道不可用。"
            case let .connectionFailed(message):
                "无法连接 Codex 本机通道：\(message)"
            case .invalidResponse:
                "Codex 返回了无效响应。"
            case let .requestFailed(message):
                "Codex 未接受请求：\(message)"
            }
        }
    }

    private let socketURL: URL
    private let timeoutSeconds: Int

    public init(
        socketURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/ipc/ipc.sock"),
        timeoutSeconds: Int = 10
    ) {
        self.socketURL = socketURL
        self.timeoutSeconds = timeoutSeconds
    }

    public func updateThreadSettings(
        threadID: String,
        model: String,
        effort: String
    ) throws {
        guard FileManager.default.fileExists(atPath: socketURL.path) else {
            throw ClientError.socketUnavailable
        }
        let descriptor = try connectSocket()
        defer { Darwin.close(descriptor) }
        let clientID = try initializeClient(on: descriptor)

        let updateID = UUID().uuidString
        try send(
            [
                "type": "request",
                "requestId": updateID,
                "sourceClientId": clientID,
                "version": 1,
                "method": "thread-follower-update-thread-settings",
                "params": [
                    "conversationId": threadID,
                    "threadSettings": ["model": model, "effort": effort],
                ],
                "timeoutMs": timeoutSeconds * 1_000,
            ],
            to: descriptor
        )
        let update = try readResponse(requestID: updateID, from: descriptor)
        guard update["resultType"] as? String == "success",
              let updateResult = update["result"] as? [String: Any],
              updateResult["ok"] as? Bool == true else {
            throw responseError(update)
        }
    }

    public func sendPrompt(
        threadID: String,
        cwd: URL,
        prompt: String,
        imagePaths: [String] = [],
        isActive: Bool
    ) throws -> PromptDisposition {
        guard FileManager.default.fileExists(atPath: socketURL.path) else {
            throw ClientError.socketUnavailable
        }
        let descriptor = try connectSocket()
        defer { Darwin.close(descriptor) }
        let clientID = try initializeClient(on: descriptor)
        let requestID = UUID().uuidString
        let messageID = UUID().uuidString
        var input: [[String: Any]] = []
        if !prompt.isEmpty {
            input.append([
                "type": "text",
                "text": prompt,
                "text_elements": [],
            ])
        }
        input.append(contentsOf: imagePaths.map {
            ["type": "localImage", "path": $0]
        })

        let method: String
        let params: [String: Any]
        if isActive {
            method = "thread-follower-steer-turn"
            params = [
                "conversationId": threadID,
                "clientUserMessageId": messageID,
                "input": input,
                "attachments": [],
                "restoreMessage": [
                    "id": messageID,
                    "text": prompt,
                    "cwd": cwd.path,
                    "createdAt": Int(Date().timeIntervalSince1970 * 1_000),
                    "context": [
                        "prompt": prompt,
                        "workspaceRoots": [cwd.path],
                        "commentAttachments": [],
                        "imageAttachments": [],
                        "fileAttachments": [],
                        "pastedTextAttachments": [],
                        "addedFiles": [],
                    ],
                ],
            ]
        } else {
            method = "thread-follower-start-turn"
            params = [
                "conversationId": threadID,
                "turnStartParams": [
                    "clientUserMessageId": messageID,
                    "input": input,
                    "cwd": cwd.path,
                    "commentAttachments": [],
                    "attachments": [],
                    "useAppServerPermissionDefault": true,
                ],
                "mcpAppModelContextAttachments": [],
            ]
        }
        try send([
            "type": "request",
            "requestId": requestID,
            "sourceClientId": clientID,
            "version": 1,
            "method": method,
            "params": params,
            "timeoutMs": timeoutSeconds * 1_000,
        ], to: descriptor)
        let response = try readResponse(requestID: requestID, from: descriptor)
        guard response["resultType"] as? String == "success" else {
            throw responseError(response)
        }
        return isActive ? .steeredActiveTurn : .startedTurn
    }

    private func initializeClient(on descriptor: Int32) throws -> String {
        let initializeID = UUID().uuidString
        try send(
            [
                "type": "request",
                "requestId": initializeID,
                "sourceClientId": "initializing-client",
                "version": 0,
                "method": "initialize",
                "params": ["clientType": "codex-hermes-touch-bar"],
                "timeoutMs": timeoutSeconds * 1_000,
            ],
            to: descriptor
        )
        let initialize = try readResponse(requestID: initializeID, from: descriptor)
        guard initialize["resultType"] as? String == "success",
              let result = initialize["result"] as? [String: Any],
              let clientID = result["clientId"] as? String else {
            throw responseError(initialize)
        }
        return clientID
    }

    private func connectSocket() throws -> Int32 {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw ClientError.connectionFailed(Self.errnoMessage())
        }
        var timeout = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        _ = withUnsafePointer(to: &timeout) {
            setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let path = socketURL.path
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else {
            Darwin.close(descriptor)
            throw ClientError.connectionFailed("Socket 路径过长")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) {
                _ = strlcpy($0, path, capacity)
            }
        }
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard status == 0 else {
            let message = Self.errnoMessage()
            Darwin.close(descriptor)
            throw ClientError.connectionFailed(message)
        }
        return descriptor
    }

    private func send(_ message: [String: Any], to descriptor: Int32) throws {
        let payload = try JSONSerialization.data(withJSONObject: message)
        let frame = CodexIPCFrameCodec.encode(payload)
        try frame.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let count = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw ClientError.connectionFailed(Self.errnoMessage())
                }
                offset += count
            }
        }
    }

    private func readResponse(requestID: String, from descriptor: Int32) throws -> [String: Any] {
        while true {
            let message = try readMessage(from: descriptor)
            if message["type"] as? String == "client-discovery-request",
               let discoveryID = message["requestId"] as? String {
                try send(CodexIPCFrameCodec.clientDiscoveryResponse(requestID: discoveryID), to: descriptor)
                continue
            }
            if message["type"] as? String == "response",
               message["requestId"] as? String == requestID {
                return message
            }
        }
    }

    private func readMessage(from descriptor: Int32) throws -> [String: Any] {
        let header = try readExactly(4, from: descriptor)
        let length = CodexIPCFrameCodec.payloadLength(header: header)
        guard length > 0, length <= 268_435_456 else {
            throw ClientError.invalidResponse
        }
        let payload = try readExactly(length, from: descriptor)
        guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw ClientError.invalidResponse
        }
        return object
    }

    private func readExactly(_ count: Int, from descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        var offset = 0
        try data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            while offset < count {
                let received = Darwin.read(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset
                )
                if received < 0, errno == EINTR { continue }
                guard received > 0 else {
                    throw ClientError.connectionFailed(Self.errnoMessage())
                }
                offset += received
            }
        }
        return data
    }

    private func responseError(_ response: [String: Any]) -> ClientError {
        if let message = response["error"] as? String {
            return .requestFailed(message)
        }
        return .invalidResponse
    }

    private static func errnoMessage() -> String {
        String(cString: strerror(errno))
    }
}

public enum CodexIPCFrameCodec {
    public static func clientDiscoveryResponse(requestID: String) -> [String: Any] {
        [
            "type": "client-discovery-response",
            "requestId": requestID,
            // This connection only originates requests; it does not implement
            // handlers for requests forwarded from other IPC clients.
            "response": ["canHandle": false],
        ]
    }

    public static func encode(_ payload: Data) -> Data {
        var length = UInt32(payload.count).littleEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        return frame
    }

    public static func payloadLength(header: Data) -> Int {
        guard header.count == 4 else { return 0 }
        return header.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            let byte0 = UInt32(bytes[0])
            let byte1 = UInt32(bytes[1]) << 8
            let byte2 = UInt32(bytes[2]) << 16
            let byte3 = UInt32(bytes[3]) << 24
            return Int(byte0 | byte1 | byte2 | byte3)
        }
    }
}
