import AppKit
import ApplicationServices

@MainActor
final class VoiceMemoLauncher {
    private struct RenameRequest: Decodable {
        let originalTitle: String
        let newTitle: String
        let recordedAt: Date
    }

    enum LauncherError: LocalizedError {
        case appUnavailable
        case accessibilityRequired
        case keyboardEventUnavailable
        case activeRecordingUnavailable
        case finishControlUnavailable
        case savedRecordingUnavailable

        var errorDescription: String? {
            switch self {
            case .appUnavailable:
                "找不到苹果“语音备忘录”App"
            case .accessibilityRequired:
                "请先允许辅助功能权限，才能一键开始录音"
            case .keyboardEventUnavailable:
                "无法发送开始录音快捷键"
            case .activeRecordingUnavailable:
                "没有检测到正在进行的语音备忘录录音"
            case .finishControlUnavailable:
                "无法操作语音备忘录的完成按钮"
            case .savedRecordingUnavailable:
                "找不到需要重命名的语音备忘录"
            }
        }
    }

    private static let voiceMemosBundleIdentifier = "com.apple.VoiceMemos"
    private static let nKeyCode: CGKeyCode = 45
    private static let pauseButtonIdentifier = "RecordingView/PauseButton"
    private static let doneButtonIdentifier = "RecordingView/DoneButton"

    static func isRecordingTitleElement(
        role: String?,
        subrole: String?,
        isEnabled: Bool,
        valueIsSettable: Bool
    ) -> Bool {
        let supportedRole = role == kAXTextFieldRole || role == kAXStaticTextRole
        return supportedRole
            && subrole != kAXSearchFieldSubrole
            && isEnabled
            && valueIsSettable
    }

    static func recordingControlMatches(
        role: String?,
        description: String?,
        title: String?,
        identifier: String?,
        descriptions: Set<String>,
        identifiers: Set<String>
    ) -> Bool {
        role == kAXButtonRole
            && (descriptions.contains(where: { $0 == description || $0 == title })
                || identifier.map(identifiers.contains) == true)
    }

    func start() async throws {
        guard AXIsProcessTrusted() else {
            throw LauncherError.accessibilityRequired
        }
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Self.voiceMemosBundleIdentifier
        ) else {
            throw LauncherError.appUnavailable
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: configuration
        )
        try await Task.sleep(for: .seconds(1.2))
        application.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: Self.nKeyCode,
                  keyDown: true
              ),
              let keyUp = CGEvent(
                  keyboardEventSource: source,
                  virtualKey: Self.nKeyCode,
                  keyDown: false
              ) else {
            throw LauncherError.keyboardEventUnavailable
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(application.processIdentifier)
        keyUp.postToPid(application.processIdentifier)
    }

    func processNextRenameRequest() async throws -> Bool {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Codex Hermes Touch Bar/voice-memo-rename-requests")
        guard let requestURL = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first else {
            return false
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let request = try decoder.decode(RenameRequest.self, from: Data(contentsOf: requestURL))
        guard !request.newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try FileManager.default.removeItem(at: requestURL)
            return true
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.voiceMemosBundleIdentifier
        ).first else {
            throw LauncherError.savedRecordingUnavailable
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        let time = Self.recordingTimeText(request.recordedAt)
        guard let row = findRecordingRow(in: appElement, originalTitle: request.originalTitle, time: time) else {
            throw LauncherError.savedRecordingUnavailable
        }
        guard AXUIElementPerformAction(row, kAXPressAction as CFString) == .success else {
            throw LauncherError.savedRecordingUnavailable
        }
        try await Task.sleep(for: .milliseconds(300))
        guard let titleField = findEditableTextField(in: appElement),
              AXUIElementSetAttributeValue(
                  titleField,
                  kAXValueAttribute as CFString,
                  request.newTitle as CFTypeRef
              ) == .success else {
            throw LauncherError.savedRecordingUnavailable
        }
        try postKey(keyCode: 36, flags: [], to: application.processIdentifier)
        try await Task.sleep(for: .milliseconds(300))
        guard findRecordingRow(in: appElement, originalTitle: request.newTitle, time: time) != nil else {
            throw LauncherError.savedRecordingUnavailable
        }
        try FileManager.default.removeItem(at: requestURL)
        return true
    }

    static func recordingRowMatches(description: String?, originalTitle: String, time: String) -> Bool {
        guard let description else { return false }
        return description.hasPrefix(originalTitle + ",") && description.contains(time)
    }

    private static func recordingTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func postKey(keyCode: CGKeyCode, flags: CGEventFlags, to pid: pid_t) throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw LauncherError.keyboardEventUnavailable
        }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }

    func finishAndKeep() async throws {
        guard AXIsProcessTrusted() else {
            throw LauncherError.accessibilityRequired
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.voiceMemosBundleIdentifier
        ).first else {
            throw LauncherError.activeRecordingUnavailable
        }
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        if let pause = findButton(
            in: appElement,
            descriptions: ["暂停", "Pause"],
            identifiers: [Self.pauseButtonIdentifier]
        ) {
            guard AXUIElementPerformAction(pause, kAXPressAction as CFString) == .success else {
                throw LauncherError.finishControlUnavailable
            }
        }
        guard let finish = await waitForButton(
            in: appElement,
            descriptions: ["完成", "Done"],
            identifiers: [Self.doneButtonIdentifier]
        ) else {
            throw LauncherError.finishControlUnavailable
        }
        guard AXUIElementPerformAction(finish, kAXPressAction as CFString) == .success else {
            throw LauncherError.finishControlUnavailable
        }
    }

    private func findButton(
        in element: AXUIElement,
        descriptions: Set<String>,
        identifiers: Set<String> = [],
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }
        let role = attribute(kAXRoleAttribute, from: element) as? String
        let description = attribute(kAXDescriptionAttribute, from: element) as? String
        let title = attribute(kAXTitleAttribute, from: element) as? String
        let identifier = attribute(kAXIdentifierAttribute, from: element) as? String
        if Self.recordingControlMatches(
            role: role,
            description: description,
            title: title,
            identifier: identifier,
            descriptions: descriptions,
            identifiers: identifiers
        ) {
            return element
        }
        guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = findButton(
                in: child,
                descriptions: descriptions,
                identifiers: identifiers,
                depth: depth + 1
            ) {
                return match
            }
        }
        return nil
    }

    private func waitForButton(
        in element: AXUIElement,
        descriptions: Set<String>,
        identifiers: Set<String>
    ) async -> AXUIElement? {
        for attempt in 0..<8 {
            if let button = findButton(
                in: element,
                descriptions: descriptions,
                identifiers: identifiers
            ) {
                return button
            }
            if attempt < 7 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        return nil
    }

    private func findRecordingRow(
        in element: AXUIElement,
        originalTitle: String,
        time: String,
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 12 else { return nil }
        let role = attribute(kAXRoleAttribute, from: element) as? String
        let description = attribute(kAXDescriptionAttribute, from: element) as? String
        if role == kAXButtonRole,
           Self.recordingRowMatches(description: description, originalTitle: originalTitle, time: time) {
            return element
        }
        guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = findRecordingRow(in: child, originalTitle: originalTitle, time: time, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func findEditableTextField(in element: AXUIElement, depth: Int = 0) -> AXUIElement? {
        guard depth < 10 else { return nil }
        let role = attribute(kAXRoleAttribute, from: element) as? String
        let subrole = attribute(kAXSubroleAttribute, from: element) as? String
        var valueIsSettable = DarwinBoolean(false)
        let settableResult = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &valueIsSettable
        )
        if Self.isRecordingTitleElement(
            role: role,
            subrole: subrole,
            isEnabled: attribute(kAXEnabledAttribute, from: element) as? Bool == true,
            valueIsSettable: settableResult == .success && valueIsSettable.boolValue
        ) {
            return element
        }
        guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = findEditableTextField(in: child, depth: depth + 1) {
                return match
            }
        }
        return nil
    }

    private func attribute(_ name: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
