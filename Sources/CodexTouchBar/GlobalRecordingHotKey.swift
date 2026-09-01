import AppKit
import Carbon.HIToolbox
import Foundation

enum RecordingHotKeyIntent: Equatable {
    case start
    case stopAndKeep

    static func resolve(isRecording: Bool) -> Self {
        isRecording ? .stopAndKeep : .start
    }
}

@MainActor
final class GlobalRecordingHotKey {
    enum HotKeyError: LocalizedError {
        case monitorRegistrationFailed

        var errorDescription: String? {
            "无法注册全局快捷键 \(GlobalRecordingHotKey.displayName)"
        }
    }

    nonisolated static let keyCode = UInt16(kVK_ANSI_R)
    nonisolated static let displayName = "Caps Lock + R"

    var onPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    nonisolated static func matches(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isRepeat: Bool
    ) -> Bool {
        guard keyCode == Self.keyCode, !isRepeat else {
            return false
        }
        let relevantModifiers: NSEvent.ModifierFlags = [
            .capsLock,
            .command, .option, .control, .shift,
        ]
        let normalizedModifiers = modifierFlags.intersection(relevantModifiers)
        let nativeCapsLock: NSEvent.ModifierFlags = [.capsLock]
        // BetterTouchTool's "Act as Hyper Key" exposes Caps Lock as the four
        // standard modifiers instead of preserving NSEvent's capsLock flag.
        let betterTouchToolHyper: NSEvent.ModifierFlags = [
            .command, .option, .control, .shift,
        ]
        return normalizedModifiers == nativeCapsLock
            || normalizedModifiers == betterTouchToolHyper
    }

    nonisolated static func matches(
        keyCode: CGKeyCode,
        flags: CGEventFlags,
        isRepeat: Bool
    ) -> Bool {
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskAlphaShift) { modifiers.insert(.capsLock) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        return matches(
            keyCode: UInt16(keyCode),
            modifierFlags: modifiers,
            isRepeat: isRepeat
        )
    }

    func unregister() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
        }
        eventTapSource = nil
        eventTap = nil
    }

    func register() throws {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw HotKeyError.monitorRegistrationFailed
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw HotKeyError.monitorRegistrationFailed
        }
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private nonisolated static let eventTapCallback: CGEventTapCallBack = {
        _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let hotKey = Unmanaged<GlobalRecordingHotKey>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Task { @MainActor in
                if let tap = hotKey.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              matches(
                keyCode: CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)),
                flags: event.flags,
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
              ) else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor in hotKey.onPressed?() }
        // A global NSEvent monitor can only observe this key. Returning nil from
        // an active event tap consumes it, so Edge does not also interpret the
        // BetterTouchTool Hyper-Key variant as Command-R and refresh the page.
        return nil
    }
}
