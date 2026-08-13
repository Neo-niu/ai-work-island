import CodexTouchBarCore
import Testing

@Test func parsesAnEffortAccessibilityDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-effort", "xhigh"])

    #expect(command == .diagnoseEffort("xhigh"))
}

@Test func keepsTheExistingRolloutDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose"])

    #expect(command == .diagnoseRollouts)
}

@Test func parsesAnAutomationDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-automation"])

    #expect(command == .diagnoseAutomation)
}

@Test func parsesAnAccessibilityTreeDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-accessibility-tree"])

    #expect(command == .diagnoseAccessibilityTree)
}

@Test func parsesAnAccessibilityPIDDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--diagnose-accessibility-pid", "6498"])

    #expect(command == .diagnoseAccessibilityPID(6498))
}

@Test func parsesAnOpenThreadDiagnostic() {
    let command = LaunchCommand(arguments: ["app", "--diagnose-open-thread", "测试新会话"])
    #expect(command == .diagnoseOpenThread("测试新会话"))
}

@Test func parsesAnOpenThreadIDDiagnostic() {
    let command = LaunchCommand(arguments: [
        "app", "--diagnose-open-thread-id", "019ff918-f2eb-73a3-a570-98baa2de51f8", "测试新会话",
    ])
    #expect(command == .diagnoseOpenThreadID(
        "019ff918-f2eb-73a3-a570-98baa2de51f8",
        "测试新会话"
    ))
}

@Test func parsesALoginItemStatusDiagnostic() {
    let command = LaunchCommand(arguments: ["CodexTouchBar", "--login-item-status"])

    #expect(command == .diagnoseLoginItem)
}
