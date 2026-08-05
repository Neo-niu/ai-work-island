import CodexTouchBarCore
import Foundation
import Testing

@Test func hermesStatusChoosesTheMostImportantCompactState() {
    #expect(HermesStatus(gatewayRunning: true, connectedPlatforms: 2, runningTasks: 3, blockedTasks: 1, failedTasks: 2).compactTitle == "Hermes !1")
    #expect(HermesStatus(gatewayRunning: true, connectedPlatforms: 2, runningTasks: 3, blockedTasks: 0, failedTasks: 2).compactTitle == "Hermes ×2")
    #expect(HermesStatus(gatewayRunning: true, connectedPlatforms: 2, runningTasks: 3, blockedTasks: 0, failedTasks: 0).compactTitle == "Hermes · 3")
    #expect(HermesStatus(gatewayRunning: true, connectedPlatforms: 2, runningTasks: 0, blockedTasks: 0, failedTasks: 0).compactTitle == "Hermes ✓")
}
