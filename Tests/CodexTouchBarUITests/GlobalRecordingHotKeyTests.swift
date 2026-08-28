import Testing
import Foundation
import ApplicationServices
import Carbon.HIToolbox
@testable import CodexTouchBar

@MainActor @Test("录音守护不读取已最小化窗口的控件树")
func recordingGuardianSkipsMinimizedWindows() {
    #expect(!VoiceMemoGuardian.shouldInspectRecordingControls(windowMinimizedStates: [true]))
    #expect(VoiceMemoGuardian.shouldInspectRecordingControls(windowMinimizedStates: [false]))
    #expect(VoiceMemoGuardian.shouldInspectRecordingControls(windowMinimizedStates: [true, false]))
    #expect(VoiceMemoGuardian.shouldInspectRecordingControls(windowMinimizedStates: []))
    #expect(VoiceMemoGuardian.shouldInspectRecordingControls(windowMinimizedStates: [nil]))
}

@Test func recordingHotKeyStartsWhenIdle() {
    #expect(RecordingHotKeyIntent.resolve(isRecording: false) == .start)
}

@Test func recordingHotKeyStopsAndKeepsWhenRecording() {
    #expect(RecordingHotKeyIntent.resolve(isRecording: true) == .stopAndKeep)
}

@MainActor @Test func recordingHotKeyUsesCapsLockAndR() {
    #expect(GlobalRecordingHotKey.keyCode == UInt16(kVK_ANSI_R))
    #expect(GlobalRecordingHotKey.displayName == "Caps Lock + R")
    #expect(GlobalRecordingHotKey.matches(
        keyCode: UInt16(kVK_ANSI_R), modifierFlags: [.capsLock], isRepeat: false
    ))
    #expect(GlobalRecordingHotKey.matches(
        keyCode: UInt16(kVK_ANSI_R),
        modifierFlags: [.command, .option, .control, .shift],
        isRepeat: false
    ))
    #expect(!GlobalRecordingHotKey.matches(
        keyCode: UInt16(kVK_ANSI_R), modifierFlags: [.capsLock, .command], isRepeat: false
    ))
    #expect(!GlobalRecordingHotKey.matches(
        keyCode: UInt16(kVK_ANSI_R), modifierFlags: [.capsLock], isRepeat: true
    ))
    #expect(!GlobalRecordingHotKey.matches(
        keyCode: UInt16(kVK_ANSI_T), modifierFlags: [.capsLock], isRepeat: false
    ))
}

@MainActor @Test func capsLockRCanBeRegisteredAsAGlobalHotKey() throws {
    let hotKey = GlobalRecordingHotKey()
    try hotKey.register()
    hotKey.unregister()
}

@MainActor @Test func recordingControlsMatchLocalizedLabelsOrStableIdentifiers() {
    #expect(VoiceMemoLauncher.recordingControlMatches(
        role: kAXButtonRole,
        description: "完成",
        title: nil,
        identifier: nil,
        descriptions: ["完成", "Done"],
        identifiers: ["RecordingView/DoneButton"]
    ))
    #expect(VoiceMemoLauncher.recordingControlMatches(
        role: kAXButtonRole,
        description: nil,
        title: nil,
        identifier: "RecordingView/DoneButton",
        descriptions: ["完成", "Done"],
        identifiers: ["RecordingView/DoneButton"]
    ))
    #expect(!VoiceMemoLauncher.recordingControlMatches(
        role: kAXStaticTextRole,
        description: "完成",
        title: nil,
        identifier: "RecordingView/DoneButton",
        descriptions: ["完成", "Done"],
        identifiers: ["RecordingView/DoneButton"]
    ))
}

@MainActor @Test func recordingTitleAcceptsSettableStaticTextUsedWhileRecording() {
    #expect(VoiceMemoLauncher.isRecordingTitleElement(
        role: kAXStaticTextRole,
        subrole: nil,
        isEnabled: true,
        valueIsSettable: true
    ))
    #expect(VoiceMemoLauncher.isRecordingTitleElement(
        role: kAXTextFieldRole,
        subrole: nil,
        isEnabled: true,
        valueIsSettable: true
    ))
}

@MainActor @Test func savedRecordingRowRequiresOriginalTitleAndRecordingTime() {
    #expect(VoiceMemoLauncher.recordingRowMatches(
        description: "北京市朝阳区 1, 16:20, 可使用听写文本",
        originalTitle: "北京市朝阳区 1",
        time: "16:20"
    ))
    #expect(!VoiceMemoLauncher.recordingRowMatches(
        description: "北京市朝阳区 1, 16:21",
        originalTitle: "北京市朝阳区 1",
        time: "16:20"
    ))
}

@MainActor @Test func recordingTitleRejectsSearchAndNonSettableText() {
    #expect(!VoiceMemoLauncher.isRecordingTitleElement(
        role: kAXTextFieldRole,
        subrole: kAXSearchFieldSubrole,
        isEnabled: true,
        valueIsSettable: true
    ))
    #expect(!VoiceMemoLauncher.isRecordingTitleElement(
        role: kAXStaticTextRole,
        subrole: nil,
        isEnabled: true,
        valueIsSettable: false
    ))
}
