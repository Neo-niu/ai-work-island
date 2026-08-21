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
        case handlerRegistrationFailed(OSStatus)
        case hotKeyRegistrationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .handlerRegistrationFailed(status):
                "无法启用录音快捷键处理器（\(status)）"
            case let .hotKeyRegistrationFailed(status):
                "无法注册全局快捷键 ⌥⌘R（\(status)）"
            }
        }
    }

    var onPressed: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    func register() throws {
        guard hotKey == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.id == 1 else { return status }
                let controller = Unmanaged<GlobalRecordingHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in controller.onPressed?() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        guard handlerStatus == noErr else {
            throw HotKeyError.handlerRegistrationFailed(handlerStatus)
        }

        let hotKeyID = EventHotKeyID(signature: 0x43485442, id: 1) // CHTB
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_R),
            UInt32(cmdKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )
        guard hotKeyStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw HotKeyError.hotKeyRegistrationFailed(hotKeyStatus)
        }
    }
}
