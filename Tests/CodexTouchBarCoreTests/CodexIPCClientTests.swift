@testable import CodexTouchBarCore
import Foundation
import Testing

@Test func codexIPCFrameUsesLittleEndianLengthPrefix() {
    let payload = Data("{\"ok\":true}".utf8)
    let frame = CodexIPCFrameCodec.encode(payload)

    #expect(CodexIPCFrameCodec.payloadLength(header: frame.prefix(4)) == payload.count)
    #expect(frame.dropFirst(4) == payload)
}

@Test func codexIPCFrameRejectsAnIncompleteHeader() {
    #expect(CodexIPCFrameCodec.payloadLength(header: Data([1, 2, 3])) == 0)
}

@Test func codexIPCClientDoesNotClaimRequestsItCannotHandle() {
    let response = CodexIPCFrameCodec.clientDiscoveryResponse(requestID: "discovery-1")

    #expect(response["type"] as? String == "client-discovery-response")
    #expect(response["requestId"] as? String == "discovery-1")
    #expect((response["response"] as? [String: Bool])?["canHandle"] == false)
}
