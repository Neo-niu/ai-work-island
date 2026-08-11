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
