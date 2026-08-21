import AppKit
@testable import CodexTouchBar
import CodexTouchBarCore
import Testing

@Test func workIslandNewThreadsUseFullAccessWithoutApprovalPrompts() {
    let cwd = URL(fileURLWithPath: "/tmp/work-island-test")
    let params = CodexConversationBridge.newThreadStartParams(cwd: cwd)

    #expect(params["cwd"] as? String == cwd.path)
    #expect(params["approvalPolicy"] as? String == "never")
    #expect(params["sandbox"] as? String == "danger-full-access")
    #expect(params["ephemeral"] as? Bool == false)

    let turnParams = CodexConversationBridge.turnStartParams(
        threadID: "thread-test",
        prompt: CodexPrompt(text: "测试", imageURLs: [])
    )
    #expect(turnParams["approvalPolicy"] as? String == "never")
    let sandboxPolicy = turnParams["sandboxPolicy"] as? [String: Any]
    #expect(sandboxPolicy?["type"] as? String == "dangerFullAccess")
}

@Test func workIslandReleasesCompletedOrTransferredThreadsWithUnsubscribe() {
    let request = CodexConversationBridge.threadUnsubscribeRequest(
        threadID: "019ffaca-d250-7b61-ba0c-56744b36a354"
    )

    #expect(request["method"] as? String == "thread/unsubscribe")
    #expect((request["id"] as? Int) == 4)
    let params = request["params"] as? [String: String]
    #expect(params?["threadId"] == "019ffaca-d250-7b61-ba0c-56744b36a354")
}

@Test func threadOwnershipTransferIsPerThreadAndRollsBackDeterministically() {
    var target = ThreadOwnershipStateMachine()
    let peer = ThreadOwnershipStateMachine()

    let began = target.beginTransfer()
    #expect(began)
    #expect(target.state == .transferring)
    #expect(peer.state == .workIsland)
    let duplicate = target.beginTransfer()
    #expect(!duplicate)
    let rolledBack = target.rollbackTransfer()
    #expect(rolledBack)
    #expect(target.state == .workIsland)
    let beganAgain = target.beginTransfer()
    let confirmed = target.confirmTransfer()
    #expect(beganAgain)
    #expect(confirmed)
    #expect(target.state == .codex)
    #expect(peer.state == .workIsland)
}

@Test func completedThreadAndTransferAcknowledgementAreIdempotent() {
    var ownership = ThreadOwnershipStateMachine()
    let began = ownership.beginTransfer()
    let confirmed = ownership.confirmTransfer()
    let duplicateConfirmation = ownership.confirmTransfer()
    let lateRollback = ownership.rollbackTransfer()
    #expect(began)
    #expect(confirmed)
    #expect(!duplicateConfirmation)
    #expect(!lateRollback)
}

@Test func unsubscribeFailureRestoresWorkIslandOwnership() {
    var ownership = ThreadOwnershipStateMachine()
    let began = ownership.beginTransfer()
    let restored = ownership.rollbackTransfer()
    #expect(began && restored)
    #expect(ownership.state == .workIsland)
}

@Test func timeoutRollbackAllowsTheThreadToTransferAgain() {
    var ownership = ThreadOwnershipStateMachine()
    _ = ownership.beginTransfer()
    _ = ownership.rollbackTransfer()
    let retried = ownership.beginTransfer()
    #expect(retried)
    #expect(ownership.state == .transferring)
}

@Test func peerTaskRemainsOwnedWhenTargetTransfers() {
    var target = ThreadOwnershipStateMachine()
    let peer = ThreadOwnershipStateMachine()
    _ = target.beginTransfer()
    _ = target.confirmTransfer()
    #expect(target.state == .codex)
    #expect(peer.state == .workIsland)
    #expect(!SharedAppServerLifetimePolicy.shouldStop(workIslandOwnedThreadCount: 1))
}

@Test func lastTransferredThreadStopsTheSharedService() {
    #expect(SharedAppServerLifetimePolicy.shouldStop(workIslandOwnedThreadCount: 0))
}

@Test func restartRecoveryTreatsMissingInProcessOwnerAsAlreadyTransferred() {
    #expect(CodexConversationBridge.ownershipState(threadID: "not-registered-after-restart") == .codex)
}

@Test func restartRecoveryStopsDurableServerOnlyWhenTargetIsTheLastActiveTask() {
    #expect(RestartRecoveryTransferPolicy.canStopServerBeforeOpening(
        hasInProcessOwner: false,
        hasOtherActiveWorkIslandThread: false
    ))
    #expect(!RestartRecoveryTransferPolicy.canStopServerBeforeOpening(
        hasInProcessOwner: true,
        hasOtherActiveWorkIslandThread: false
    ))
    #expect(!RestartRecoveryTransferPolicy.canStopServerBeforeOpening(
        hasInProcessOwner: false,
        hasOtherActiveWorkIslandThread: true
    ))
}

@Test func restartRecoveryWaitsOnlyForOtherActiveWorkIslandTasks() {
    #expect(RestartRecoveryTransferPolicy.shouldWaitForPeerTasks(
        hasInProcessOwner: false,
        hasOtherActiveWorkIslandThread: true
    ))
    #expect(!RestartRecoveryTransferPolicy.shouldWaitForPeerTasks(
        hasInProcessOwner: true,
        hasOtherActiveWorkIslandThread: true
    ))
    #expect(!RestartRecoveryTransferPolicy.shouldWaitForPeerTasks(
        hasInProcessOwner: false,
        hasOtherActiveWorkIslandThread: false
    ))
}

@Test func everyUserOpenEntryRoutesRetainedThreadsThroughWorkIslandTransfer() {
    let retainedThreadID = "019ffaca-d250-7b61-ba0c-56744b36a354"
    let retained = Set([retainedThreadID])

    #expect(CodexThreadOpeningPolicy.requiresWorkIslandTransfer(
        threadID: retainedThreadID,
        retainedWorkIslandThreadIDs: retained
    ))
    #expect(!CodexThreadOpeningPolicy.requiresWorkIslandTransfer(
        threadID: "019ffb2e-bb82-7d51-a642-fc031f582e78",
        retainedWorkIslandThreadIDs: retained
    ))
}

@Test func waitingCodexCardOpensItsThreadBeforeShowingGenericIssueDetails() {
    let waitingCodex = WorkItem(
        id: "codex:019fffa3-7e30-78e3-a7cb-29930bae01ff",
        source: "Codex",
        title: "快捷键地图卡死了",
        status: .waiting,
        updatedAt: Date()
    )
    let failedAutomation = WorkItem(
        id: "automation:failed",
        source: "自动化",
        title: "失败任务",
        status: .failed,
        updatedAt: Date()
    )

    #expect(WorkItemPrimaryAction.resolve(waitingCodex) == .codexThread)
    #expect(WorkItemPrimaryAction.resolve(failedAutomation) == .issue)
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
@Test func commandVPastesPlainTextEvenWithoutAnActiveFieldEditor() throws {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    defer { pasteboard.clearContents() }
    #expect(pasteboard.setString("粘贴的新任务", forType: .string))

    let field = PastedImageTextField(string: "已有：")
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
    #expect(field.stringValue == "已有：粘贴的新任务")
    #expect(field.pastedImageCount == 0)
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
