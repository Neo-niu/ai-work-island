import AppKit
import ApplicationServices

@MainActor
final class VoiceMemoLauncher {
    enum LauncherError: LocalizedError {
        case appUnavailable
        case accessibilityRequired
        case keyboardEventUnavailable
        case activeRecordingUnavailable
        case finishControlUnavailable

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
            }
        }
    }

    private static let voiceMemosBundleIdentifier = "com.apple.VoiceMemos"
    private static let nKeyCode: CGKeyCode = 45

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
        if let pause = findButton(in: appElement, descriptions: ["暂停", "Pause"]) {
            AXUIElementPerformAction(pause, kAXPressAction as CFString)
            try await Task.sleep(for: .milliseconds(250))
        }
        guard let finish = findButton(in: appElement, descriptions: ["完成", "Done"]) else {
            throw LauncherError.finishControlUnavailable
        }
        guard AXUIElementPerformAction(finish, kAXPressAction as CFString) == .success else {
            throw LauncherError.finishControlUnavailable
        }
    }

    private func findButton(
        in element: AXUIElement,
        descriptions: Set<String>,
        depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 10 else { return nil }
        let role = attribute(kAXRoleAttribute, from: element) as? String
        let description = attribute(kAXDescriptionAttribute, from: element) as? String
        let title = attribute(kAXTitleAttribute, from: element) as? String
        if role == kAXButtonRole,
           descriptions.contains(where: { $0 == description || $0 == title }) {
            return element
        }
        guard let children = attribute(kAXChildrenAttribute, from: element) as? [AXUIElement] else {
            return nil
        }
        for child in children {
            if let match = findButton(in: child, descriptions: descriptions, depth: depth + 1) {
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
