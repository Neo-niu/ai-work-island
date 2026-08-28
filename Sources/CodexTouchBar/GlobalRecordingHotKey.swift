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

    private var globalMonitor: Any?
    private var localMonitor: Any?

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

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    func register() throws {
        guard globalMonitor == nil, localMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                isRepeat: event.isARepeat
            ) else { return }
            Task { @MainActor [weak self] in self?.onPressed?() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.matches(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                isRepeat: event.isARepeat
            ) else { return event }
            self?.onPressed?()
            return nil
        }

        guard globalMonitor != nil, localMonitor != nil else {
            unregister()
            throw HotKeyError.monitorRegistrationFailed
        }
    }
}
