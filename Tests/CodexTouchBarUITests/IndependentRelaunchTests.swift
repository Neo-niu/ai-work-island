@testable import CodexTouchBar
import Foundation
import Testing

@Test func durableAppServerListensOnAUnixSocket() {
    let socketURL = URL(fileURLWithPath: "/tmp/ai-work-island/app-server.sock")
    let arguments = DurableCodexAppServer.launchctlSubmitArguments(
        executableURL: URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
        socketURL: socketURL
    )
    #expect(arguments.contains("--listen"))
    #expect(arguments.contains("unix:///tmp/ai-work-island/app-server.sock"))
    #expect(arguments.contains(DurableCodexAppServer.launchLabel))
}

@Test func independentRelaunchIsOwnedByLaunchd() {
    let arguments = IndependentAppRelauncher.launchctlArguments(
        bundlePath: "/Applications/AI工作岛.app",
        currentPID: 4321
    )

    #expect(arguments.prefix(3) == ["submit", "-l", IndependentAppRelauncher.launchLabel])
    #expect(arguments.contains(where: {
        $0.contains("launchctl remove \(IndependentAppRelauncher.launchLabel)")
    }))
    #expect(arguments.contains("/bin/sh"))
    #expect(arguments.contains("4321"))
    #expect(arguments.contains("/Applications/AI工作岛.app"))
    #expect(!arguments.joined(separator: " ").contains("open -n"))
}
