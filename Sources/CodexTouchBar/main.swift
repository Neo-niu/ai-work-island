import AppKit
import CodexTouchBarCore
import Darwin

@MainActor
private func runApplication() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
}

private func runDiagnostics() {
    let scanner = RolloutScanner()
    let grouper = ProjectGrouper()

    Task {
        let snapshot = await scanner.scanSnapshot()
        if let shortTermLimit = snapshot.shortTermLimit {
            print("5-hour limit\t\(shortTermLimit.remainingPercent)% remaining")
        } else {
            print("5-hour limit\tUnavailable")
        }
        if let weeklyLimit = snapshot.weeklyLimit {
            print("Weekly limit\t\(weeklyLimit.remainingPercent)% remaining")
        } else {
            print("Weekly limit\tUnavailable")
        }
        print("Unread threads\t\(snapshot.threads.filter(\.isUnread).count)")
        let selectedProjects = snapshot.selectedProjectRoots.map(\.lastPathComponent)
        print("Selected projects\t\(selectedProjects.joined(separator: ","))")

        let groups = grouper.groups(
            from: snapshot.threads,
            selectedProjectRoots: snapshot.selectedProjectRoots
        )
        if groups.isEmpty {
            print("No active Codex tasks")
        } else {
            for group in groups {
                let state = [
                    group.hasUnread ? "unread" : nil,
                    group.isSelected ? "selected" : nil,
                ]
                .compactMap { $0 }
                .joined(separator: ",")
                print("\(group.name)\t\(group.threads.count)\t\(state)\t\(group.threads.map(\.id).joined(separator: ","))")
            }
        }
        exit(EXIT_SUCCESS)
    }
    dispatchMain()
}

private func runHermesDiagnostics() {
    let status = HermesStatusScanner().scan()
    print("Gateway\t\(status.gatewayRunning ? "running" : "stopped")")
    print("Connected platforms\t\(status.connectedPlatforms)")
    print("Running tasks\t\(status.runningTasks)")
    print("Blocked tasks\t\(status.blockedTasks)")
    print("Failed tasks\t\(status.failedTasks)")
    print("Touch Bar title\t\(status.compactTitle)")
}

private func runAutomationDiagnostics() {
    let scanner = AutomationStatusScanner()
    let result = scanner.scan()
    print("Status directory\t\(scanner.statusDirectory.path)")
    print("Automation tasks\t\(result.items.count)")
    for item in result.items {
        print("\(item.status.rawValue)\t\(item.source)\t\(item.title)\t\(item.updatedAt.ISO8601Format())")
    }
    for issue in result.issues {
        print("Issue\t\(issue)")
    }
    exit(result.issues.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
}

private func runCompanyQuotaDiagnostics() {
    let scanner = CompanyQuotaScanner()
    Task {
        if let quota = await scanner.scanIfNeeded() {
            print("Company quota\t\(quota.remainingPercent)% remaining")
            print(String(format: "Remaining USD\t$%.2f", quota.remainingUSD))
            print(String(format: "Used USD\t$%.2f / $%.2f", quota.usedUSD, quota.totalUSD))
            exit(EXIT_SUCCESS)
        } else {
            print("Company quota\tUnavailable; keep a signed-in model.zhenguanyu.com tab open in Edge")
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
}

@MainActor
private func runEffortDiagnostic(rawValue: String) {
    guard let choice = EffortChoice(rawValue: rawValue) else {
        print("Unknown effort choice: \(rawValue)")
        exit(EXIT_FAILURE)
    }

    let scanner = RolloutScanner()
    let client = CodexIPCClient()
    Task {
        do {
            guard let setting = await scanner.currentThreadReasoningSetting() else {
                throw CodexIPCClient.ClientError.requestFailed("未找到当前任务")
            }
            try await client.updateThreadSettings(
                threadID: setting.threadID,
                model: setting.model,
                effort: choice.rawValue
            )
            for _ in 0..<50 {
                if await scanner.currentThreadReasoningSetting()?.effort == choice.rawValue {
                    print("Selected effort: \(choice.title)")
                    exit(EXIT_SUCCESS)
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw CodexIPCClient.ClientError.requestFailed("数据库回读未确认")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("Codex IPC diagnostic failed: \(message)")
            exit(EXIT_FAILURE)
        }
    }
    dispatchMain()
}

@MainActor
private func runAccessibilityTreeDiagnostic(processIdentifier: pid_t? = nil) {
    let controller = CodexAccessibilityController()
    do {
        let lines = try controller.diagnosticAccessibilityTree(processIdentifier: processIdentifier)
        lines.forEach { print($0) }
        exit(EXIT_SUCCESS)
    } catch {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        print("Accessibility tree diagnostic failed: \(message)")
        exit(EXIT_FAILURE)
    }
}

switch LaunchCommand(arguments: CommandLine.arguments) {
case .diagnoseRollouts:
    runDiagnostics()
case .diagnoseHermes:
    runHermesDiagnostics()
case .diagnoseAutomation:
    runAutomationDiagnostics()
case .diagnoseCompanyQuota:
    runCompanyQuotaDiagnostics()
case let .diagnoseEffort(rawValue):
    runEffortDiagnostic(rawValue: rawValue)
case .diagnoseAccessibilityTree:
    runAccessibilityTreeDiagnostic()
case let .diagnoseAccessibilityPID(processIdentifier):
    runAccessibilityTreeDiagnostic(processIdentifier: processIdentifier)
case .diagnoseLoginItem:
    print(LaunchAtLoginController.statusDescription)
case .run:
    runApplication()
}
