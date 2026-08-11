import AppKit
import ApplicationServices

@MainActor
final class VoiceMemoLauncher {
    enum LauncherError: LocalizedError {
        case appUnavailable
        case accessibilityRequired
        case keyboardEventUnavailable

        var errorDescription: String? {
            switch self {
            case .appUnavailable:
                "找不到苹果“语音备忘录”App"
            case .accessibilityRequired:
                "请先允许辅助功能权限，才能一键开始录音"
            case .keyboardEventUnavailable:
                "无法发送开始录音快捷键"
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
}
