import AppKit
@testable import CodexTouchBar
import Testing

@Test func workIslandNewThreadsUseFullAccessWithoutApprovalPrompts() {
    let cwd = URL(fileURLWithPath: "/tmp/work-island-test")
    let params = CodexConversationBridge.newThreadStartParams(cwd: cwd)

    #expect(params["cwd"] as? String == cwd.path)
    #expect(params["approvalPolicy"] as? String == "never")
    #expect(params["sandbox"] as? String == "danger-full-access")
    #expect(params["ephemeral"] as? Bool == false)
}

@MainActor
@Test func commandVPastesAnImageIntoTheConversationPrompt() throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }

    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    #expect(pasteboard.writeObjects([image]))

    let field = PastedImageTextField(string: "请分析")
    let event = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: .command,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "v",
        charactersIgnoringModifiers: "v",
        isARepeat: false,
        keyCode: 9
    ))

    #expect(field.performKeyEquivalent(with: event))
    #expect(field.pastedImageCount == 1)
    let prompt = field.takePrompt()
    #expect(prompt.text == "请分析")
    #expect(prompt.imageURLs.count == 1)
    #expect(FileManager.default.fileExists(atPath: prompt.imageURLs[0].path))
    try FileManager.default.removeItem(at: prompt.imageURLs[0])
}

@MainActor
@Test func deleteRemovesTheLastPastedImageWhenTheTextFieldIsEmpty() throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    #expect(pasteboard.writeObjects([image]))

    let field = PastedImageTextField(string: "")
    let pasteEvent = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v",
        isARepeat: false, keyCode: 9
    ))
    #expect(field.performKeyEquivalent(with: pasteEvent))
    #expect(field.pastedImageCount == 1)

    let deleteEvent = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}",
        isARepeat: false, keyCode: 51
    ))
    #expect(field.performKeyEquivalent(with: deleteEvent))
    #expect(field.pastedImageCount == 0)
}

@MainActor
@Test func fieldEditorDeleteCommandRemovesTheLastPastedImage() throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.systemBlue.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()
    #expect(pasteboard.writeObjects([image]))

    let field = PastedImageTextField(string: "")
    let pasteEvent = try #require(NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: 0, context: nil, characters: "v", charactersIgnoringModifiers: "v",
        isARepeat: false, keyCode: 9
    ))
    #expect(field.performKeyEquivalent(with: pasteEvent))
    #expect(field.handleDeleteCommand(#selector(NSResponder.deleteBackward(_:))))
    #expect(field.pastedImageCount == 0)
}
