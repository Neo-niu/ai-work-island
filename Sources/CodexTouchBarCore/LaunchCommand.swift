public enum LaunchCommand: Equatable, Sendable {
    case run
    case diagnoseRollouts
    case diagnoseHermes
    case diagnoseAutomation
    case diagnoseCompanyQuota
    case diagnoseEffort(String)
    case diagnoseAccessibilityTree
    case diagnoseAccessibilityPID(Int32)
    case diagnoseOpenThread(String)
    case diagnoseOpenThreadID(String, String)
    case diagnoseLoginItem

    public init(arguments: [String]) {
        if let index = arguments.firstIndex(of: "--diagnose-open-thread-id"),
           arguments.indices.contains(index + 2) {
            self = .diagnoseOpenThreadID(arguments[index + 1], arguments[index + 2])
        } else if let index = arguments.firstIndex(of: "--diagnose-open-thread"),
           arguments.indices.contains(index + 1) {
            self = .diagnoseOpenThread(arguments[index + 1])
        } else if let index = arguments.firstIndex(of: "--diagnose-accessibility-pid"),
           arguments.indices.contains(index + 1),
           let processIdentifier = Int32(arguments[index + 1]) {
            self = .diagnoseAccessibilityPID(processIdentifier)
        } else if arguments.contains("--diagnose-automation") {
            self = .diagnoseAutomation
        } else if arguments.contains("--diagnose-company-quota") {
            self = .diagnoseCompanyQuota
        } else if arguments.contains("--diagnose-hermes") {
            self = .diagnoseHermes
        } else if arguments.contains("--login-item-status") {
            self = .diagnoseLoginItem
        } else if arguments.contains("--diagnose-accessibility-tree") {
            self = .diagnoseAccessibilityTree
        } else if let index = arguments.firstIndex(of: "--diagnose-effort"),
           arguments.indices.contains(index + 1) {
            self = .diagnoseEffort(arguments[index + 1])
        } else if arguments.contains("--diagnose") {
            self = .diagnoseRollouts
        } else {
            self = .run
        }
    }
}
