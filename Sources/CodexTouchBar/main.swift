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

    let controller = CodexAccessibilityController()
    Task { @MainActor in
        do {
            try await controller.apply(effort: choice)
            print("Selected effort: \(choice.title)")
            exit(EXIT_SUCCESS)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            print("Accessibility diagnostic failed: \(message)")
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
