import AppKit
import ApplicationServices
import CodexTouchBarCore

@MainActor
final class CodexAccessibilityController {
    private static let codexBundleIdentifier = "com.openai.codex"

    enum ControlKind {
        case effort
        case speed

        var openerKeywords: [String] {
            switch self {
            case .effort:
                ["çaba", "effort", "reasoning", "推理", "思考", "程度"]
            case .speed:
                ["hız", "speed", "service tier"]
            }
        }

        var currentValueLabels: [String] {
            switch self {
            case .effort:
                EffortChoice.allCases.flatMap(\.accessibilityLabels)
            case .speed:
                SpeedChoice.allCases.flatMap(\.accessibilityLabels)
            }
        }
    }

    enum ControllerError: LocalizedError {
        case accessibilityPermissionRequired
        case codexNotRunning
        case codexMustBeFrontmost
        case codexRestartRequired
        case commandBridgeUnavailable(String)
        case controlNotFound(ControlKind)
        case optionNotFound(String)
        case actionFailed
        case threadTitleUnavailable
        case threadNotVisible

        var errorDescription: String? {
            switch self {
            case .accessibilityPermissionRequired:
                "请在系统设置 → 隐私与安全性 → 辅助功能中启用本应用，然后重试。"
            case .codexNotRunning:
                "Codex 当前未运行。"
            case .codexMustBeFrontmost:
                "请先在 Codex 中打开一个任务，然后重试。"
            case .codexRestartRequired:
                "请退出并重新打开一次 Codex，以启用推理程度控制。"
            case let .commandBridgeUnavailable(message):
                "无法准备 Codex 控制桥接：\(message)"
            case .controlNotFound(.effort):
                "当前 Codex 任务中未找到推理程度控件。"
            case .controlNotFound(.speed):
                "当前 Codex 任务中未找到响应速度控件。"
            case let .optionNotFound(option):
                "未找到 Codex 选项“\(option)”。"
            case .actionFailed:
                "Codex 未接受本次设置更改。"
            case .threadTitleUnavailable:
                "无法读取目标会话标题。"
            case .threadNotVisible:
                "目标任务不在当前 Codex 侧栏中；未执行输入操作。"
            }
        }
    }

    func requestAccessibilityAccess() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func hasAccessibilityAccess() -> Bool {
        AXIsProcessTrusted()
    }

    func selectedSidebarProjectName() -> String? {
        guard AXIsProcessTrusted(),
              let application = NSRunningApplication.runningApplications(
                  withBundleIdentifier: Self.codexBundleIdentifier
              ).first else {
            return nil
        }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        _ = enableEnhancedAccessibility(for: root)
        let rows = accessibilityElements(in: root, sidebarOnly: true).compactMap {
            snapshot -> SidebarSelectionRow? in
            guard snapshot.role == (kAXButtonRole as String),
                  let frame = rectAttribute("AXFrame", of: snapshot.element),
                  frame.minX < 20 else {
                return nil
            }

            let classes = stringListAttribute("AXDOMClassList", of: snapshot.element)
            if classes.contains("group/folder-row"), !snapshot.rawText.isEmpty {
                if classes.contains("bg-token-list-hover-background") {
                    return .selectedProject(
                        name: snapshot.rawText,
                        minY: frame.minY,
                        height: frame.height
                    )
                } else {
                    return .project(
                        name: snapshot.rawText,
                        minY: frame.minY,
                        height: frame.height
                    )
                }
            }
            if classes.contains("bg-token-list-hover-background") {
                return .selectedTask(minY: frame.minY, height: frame.height)
            }
            return nil
        }
        return SidebarSelectionResolver.projectName(from: rows)
    }

    func apply(effort choice: EffortChoice) async throws {
        do {
            try await select(
                kind: .effort,
                labels: choice.accessibilityLabels,
                displayName: choice.title
            )
            return
        } catch let error as ControllerError {
            switch error {
            case .controlNotFound(.effort):
                throw error
            case .optionNotFound, .actionFailed:
                break
            default:
                throw error
            }
        }

        try prepareCommandBridge()
        let commands = CodexCommandPlan.effort(
            targetIndex: choice.commandTargetIndex,
            optionCount: EffortChoice.commandOptionCount
        )
        guard !commands.isEmpty else {
            throw ControllerError.actionFailed
        }
        try await send(commands)
    }

    func apply(speed choice: SpeedChoice) async throws {
        try prepareCommandBridge()
        let targetServiceTier = choice.rawValue
        if currentServiceTier() == targetServiceTier {
            return
        }
        try await send([.toggleFastMode])

        if currentServiceTier() != nil {
            for _ in 0..<12 {
                if currentServiceTier() == targetServiceTier {
                    return
                }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            throw ControllerError.actionFailed
        }
    }

    func openVisibleThread(title: String) async throws {
        let query = title.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            throw ControllerError.threadTitleUnavailable
        }
        guard hasAccessibilityAccess() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first else {
            throw ControllerError.codexNotRunning
        }
        if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Self.codexBundleIdentifier {
            application.activate(options: [.activateIgnoringOtherApps])
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        _ = enableEnhancedAccessibility(for: root)
        let target = normalized(String(query.prefix(120)))
        // A Work Island thread can reach the persistent index several seconds
        // before Codex renders its sidebar row.  Do not fall back to a deep
        // link here: that path can open a conversation but still fail the
        // post-open accessibility check, which incorrectly restores “等待你”.
        for _ in 0..<80 {
            let match = bestThreadMatch(target: target, in: accessibilityElements(in: root, sidebarOnly: true))
            if let match {
                guard AXUIElementPerformAction(match, kAXPressAction as CFString) == .success else {
                    throw ControllerError.actionFailed
                }
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw ControllerError.threadNotVisible
    }

    func openThread(threadID: String, title: String) async throws {
        guard UUID(uuidString: threadID) != nil,
              let url = URL(string: "codex://threads/\(threadID)") else {
            throw ControllerError.actionFailed
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first else {
            throw ControllerError.codexNotRunning
        }
        application.activate(options: [.activateIgnoringOtherApps])
        try await Task.sleep(nanoseconds: 150_000_000)
        let root = AXUIElementCreateApplication(application.processIdentifier)
        _ = enableEnhancedAccessibility(for: root)
        if focusedRole(in: root) == (kAXComboBoxRole as String) {
            try dismissCommandPalette()
            try await Task.sleep(nanoseconds: 150_000_000)
        }
        guard NSWorkspace.shared.open(url) else {
            throw ControllerError.actionFailed
        }

        // Current Codex builds route this stable ID to the most recently focused
        // main window. Keep the accessibility check as an opportunistic error
        // detector, not as the success condition: recent ChatGPT/Codex builds can
        // navigate correctly while exposing only the native window chrome to AX.
        let target = normalized(String(title.prefix(120)))
        for _ in 0..<20 {
            let elements = accessibilityElements(in: root)
            if elements.contains(where: {
                $0.text.contains("conversation state not found") ||
                $0.text.contains("未找到对话")
            }) {
                throw ControllerError.threadNotVisible
            }
            if elements.contains(where: { snapshot in
                guard let frame = rectAttribute("AXFrame", of: snapshot.element),
                      frame.minX >= 220 else { return false }
                return snapshot.text.contains(target)
            }) {
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        // NSWorkspace accepted the stable-ID route and Codex exposed no contrary
        // evidence. Treat the dispatch as successful; title-only sidebar lookup
        // cannot distinguish duplicate titles and misses newly indexed threads.
    }

    private func focusedRole(in root: AXUIElement) -> String? {
        guard let focused = attribute(kAXFocusedUIElementAttribute, of: root),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        return stringAttribute(
            kAXRoleAttribute,
            of: unsafeDowncast(focused, to: AXUIElement.self)
        )
    }

    private func dismissCommandPalette() throws {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false) else {
            throw ControllerError.actionFailed
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func bestThreadMatch(target: String, in elements: [ElementSnapshot]) -> AXUIElement? {
        elements.compactMap { snapshot -> (AXUIElement, Int, Int)? in
            guard snapshot.canPress,
                  snapshot.role == (kAXButtonRole as String) else {
                return nil
            }
            let candidate = normalized(snapshot.rawText)
            let score: Int
            if candidate == target {
                score = 100
            } else if candidate.hasPrefix("\(target) ") {
                score = 90
            } else if candidate.contains(target), target.count >= 6 {
                score = 70
            } else {
                return nil
            }
            return (snapshot.element, score, candidate.count)
        }
        .max {
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            return $0.2 > $1.2
        }?
        .0
    }

    private func prepareCommandBridge() throws {
        guard hasAccessibilityAccess() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier else {
            throw ControllerError.codexMustBeFrontmost
        }
        guard let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first else {
            throw ControllerError.codexNotRunning
        }

        let fileManager = FileManager.default
        let codexDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
        let keymapURL = codexDirectory.appendingPathComponent("keybindings.json")
        do {
            let existingData: Data?
            if fileManager.fileExists(atPath: keymapURL.path) {
                existingData = try Data(contentsOf: keymapURL)
            } else {
                existingData = nil
            }
            let mergedData = try CodexCommandKeymap.mergingPrivateBindings(into: existingData)
            if mergedData != existingData {
                try fileManager.createDirectory(at: codexDirectory, withIntermediateDirectories: true)
                try mergedData.write(to: keymapURL, options: .atomic)
            }
            let keymapModificationDate = try keymapURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate
            if CodexCommandBridgeRuntime.requiresRestart(
                codexLaunchDate: codex.launchDate,
                keymapModificationDate: keymapModificationDate
            ) {
                throw ControllerError.codexRestartRequired
            }
        } catch let error as ControllerError {
            throw error
        } catch {
            throw ControllerError.commandBridgeUnavailable(error.localizedDescription)
        }
    }

    private func send(_ commands: [CodexCommand]) async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
        var previousCommand: CodexCommand?
        for command in commands {
            if previousCommand == .decreaseEffort, command == .increaseEffort {
                // Boundary decreases do not change the visible value, but Codex
                // still processes them asynchronously. Let the reset queue drain
                // before applying the target steps or the first increase is lost.
                try await Task.sleep(nanoseconds: 1_500_000_000)
            }
            guard postKey(for: command) else {
                throw ControllerError.actionFailed
            }
            // Codex persists reasoning changes asynchronously. Sending the reset
            // and target steps too quickly drops intermediate commands and can
            // leave the composer at a lower effort than requested.
            try await Task.sleep(nanoseconds: 550_000_000)
            previousCommand = command
        }
    }

    private func postKey(for command: CodexCommand) -> Bool {
        let keyCode: CGKeyCode
        switch command {
        case .increaseEffort:
            keyCode = 64 // F17
        case .decreaseEffort:
            keyCode = 79 // F18
        case .toggleFastMode:
            keyCode = 80 // F19
        }

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        let flags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }


    private func currentServiceTier() -> String? {
        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/config.toml")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8),
              let expression = try? NSRegularExpression(
                  pattern: #"(?m)^\s*service_tier\s*=\s*\"([^\"]+)\""#
              ),
              let match = expression.firstMatch(
                  in: contents,
                  range: NSRange(contents.startIndex..., in: contents)
              ),
              let valueRange = Range(match.range(at: 1), in: contents) else {
            return nil
        }
        return String(contents[valueRange])
    }

    func diagnosticAccessibilityTree(processIdentifier: pid_t? = nil) throws -> [String] {
        guard AXIsProcessTrusted() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        let targetPID: pid_t
        if let processIdentifier {
            targetPID = processIdentifier
        } else {
            guard let application = NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.codexBundleIdentifier
            ).first else {
                throw ControllerError.codexNotRunning
            }
            targetPID = application.processIdentifier
        }

        let root = AXUIElementCreateApplication(targetPID)
        let activationError = enableEnhancedAccessibility(for: root)
        let keywords = [
            "çaba", "effort", "reasoning", "yüksek", "high", "hız", "speed",
            "推理", "思考", "程度", "轻度", "中度", "高度", "极高", "max", "ultra",
        ]
        var lines = [
            "enhancedActivation.error=\(activationError.rawValue)",
            "application.attributes=\(attributeNames(of: root).joined(separator: ","))",
        ]
        if let focusedWindow = attribute(kAXFocusedWindowAttribute, of: root),
           CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            let window = unsafeDowncast(focusedWindow, to: AXUIElement.self)
            lines.append("window.attributes=\(attributeNames(of: window).joined(separator: ","))")
        }
        if let focusedValue = attribute(kAXFocusedUIElementAttribute, of: root),
           CFGetTypeID(focusedValue) == AXUIElementGetTypeID() {
            let focused = unsafeDowncast(focusedValue, to: AXUIElement.self)
            lines.append("focused.role=\(stringAttribute(kAXRoleAttribute, of: focused))")
            lines.append("focused.text=\(stringAttribute(kAXTitleAttribute, of: focused)) \(stringAttribute(kAXDescriptionAttribute, of: focused)) \(stringAttribute(kAXValueAttribute, of: focused))")
            lines.append("focused.actions=\(actionNames(of: focused).joined(separator: ","))")
            lines.append("focused.attributes=\(attributeNames(of: focused).joined(separator: ","))")
        }
        lines.append(contentsOf: accessibilityElements(in: root)
            .compactMap { snapshot -> String? in
                let actions = actionNames(of: snapshot.element)
                let frame = rectAttribute("AXFrame", of: snapshot.element)
                let isInSidebar = frame.map { $0.minX < 650 } ?? false
                guard isInSidebar || keywords.contains(where: snapshot.text.contains) else {
                    return nil
                }
                let classes = stringListAttribute("AXDOMClassList", of: snapshot.element)
                let selected = booleanAttribute(kAXSelectedAttribute, of: snapshot.element)
                let frameText = frame.map {
                    "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))"
                } ?? "-"
                return "depth=\(snapshot.depth) role=\(snapshot.role) selected=\(selected) frame=\(frameText) classes=\(classes.joined(separator: ",")) actions=\(actions.joined(separator: ",")) text=\(snapshot.text)"
            })
        return lines
    }

    private func select(kind: ControlKind, labels: [String], displayName: String) async throws {
        guard hasAccessibilityAccess() else {
            throw ControllerError.accessibilityPermissionRequired
        }
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier else {
            throw ControllerError.codexMustBeFrontmost
        }
        guard let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
        ).first else {
            throw ControllerError.codexNotRunning
        }

        let root = AXUIElementCreateApplication(application.processIdentifier)
        _ = enableEnhancedAccessibility(for: root)
        let initialElements = accessibilityElements(in: root)
        guard let opener = bestOpener(for: kind, among: initialElements) else {
            throw ControllerError.controlNotFound(kind)
        }
        guard AXUIElementPerformAction(opener, kAXPressAction as CFString) == .success else {
            throw ControllerError.actionFailed
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        let expandedElements = accessibilityElements(in: root)
        guard let option = bestOption(matching: labels, excluding: opener, among: expandedElements) else {
            throw ControllerError.optionNotFound(displayName)
        }
        guard AXUIElementPerformAction(option, kAXPressAction as CFString) == .success else {
            throw ControllerError.actionFailed
        }
    }

    private struct ElementSnapshot {
        let element: AXUIElement
        let depth: Int
        let role: String
        let rawText: String
        let text: String
        let canPress: Bool
    }

    private func enableEnhancedAccessibility(for application: AXUIElement) -> AXError {
        AXUIElementSetAttributeValue(
            application,
            AccessibilityRuntimePolicy.activationAttribute as CFString,
            kCFBooleanTrue
        )
    }

    private func accessibilityElements(
        in application: AXUIElement,
        sidebarOnly: Bool = false
    ) -> [ElementSnapshot] {
        let roots: [AXUIElement]
        if let focusedWindow = attribute(kAXFocusedWindowAttribute, of: application),
           CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() {
            roots = [unsafeDowncast(focusedWindow, to: AXUIElement.self)]
        } else if let windows = attribute(kAXWindowsAttribute, of: application) as? [AXUIElement] {
            roots = windows
        } else {
            roots = [application]
        }

        var result: [ElementSnapshot] = []
        var queue = roots.map { ($0, 0) }
        var cursor = 0
        var visited: Set<CFHashCode> = []

        while cursor < queue.count, result.count < 5_000 {
            let (element, depth) = queue[cursor]
            cursor += 1

            let elementHash = CFHash(element)
            guard visited.insert(elementHash).inserted else {
                continue
            }

            let role = stringAttribute(kAXRoleAttribute, of: element)
            let text = [
                stringAttribute(kAXTitleAttribute, of: element),
                stringAttribute(kAXDescriptionAttribute, of: element),
                stringAttribute(kAXHelpAttribute, of: element),
                stringAttribute(kAXValueAttribute, of: element),
                stringAttribute(kAXIdentifierAttribute, of: element),
            ]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            let actions = actionNames(of: element)
            result.append(
                ElementSnapshot(
                    element: element,
                    depth: depth,
                    role: role,
                    rawText: text,
                    text: normalized(text),
                    canPress: actions.contains(kAXPressAction as String)
                )
            )

            guard depth < AccessibilityRuntimePolicy.maximumTraversalDepth else {
                continue
            }
            if sidebarOnly,
               depth >= 12,
               let frame = rectAttribute("AXFrame", of: element),
               frame.minX >= 300 {
                continue
            }
            for childAttribute in AccessibilityRuntimePolicy.childAttributeNames {
                guard let children = attribute(childAttribute, of: element) as? [AXUIElement] else {
                    continue
                }
                queue.append(contentsOf: children.map { ($0, depth + 1) })
            }
        }

        return result
    }

    private func bestOpener(for kind: ControlKind, among elements: [ElementSnapshot]) -> AXUIElement? {
        let keywords = kind.openerKeywords.map(normalized)
        let values = kind.currentValueLabels.map(normalized)

        return elements
            .compactMap { snapshot -> (AXUIElement, Int)? in
                guard snapshot.canPress else {
                    return nil
                }
                var score = 0
                if keywords.contains(where: snapshot.text.contains) {
                    score += 100
                }
                if values.contains(where: { snapshot.text == $0 || snapshot.text.hasPrefix("\($0) ") }) {
                    score += 45
                }
                if snapshot.role == (kAXPopUpButtonRole as String) || snapshot.role == (kAXButtonRole as String) {
                    score += 10
                }
                return score >= 55 ? (snapshot.element, score) : nil
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func bestOption(
        matching labels: [String],
        excluding opener: AXUIElement,
        among elements: [ElementSnapshot]
    ) -> AXUIElement? {
        let normalizedLabels = labels.map(normalized)

        return elements
            .compactMap { snapshot -> (AXUIElement, Int)? in
                guard snapshot.canPress, !CFEqual(snapshot.element, opener) else {
                    return nil
                }

                var score = 0
                if normalizedLabels.contains(snapshot.text) {
                    score += 100
                } else if normalizedLabels.contains(where: {
                    snapshot.text.hasPrefix("\($0) ") || snapshot.text.contains(" \($0) ")
                }) {
                    score += 70
                }
                if snapshot.role == (kAXMenuItemRole as String) || snapshot.role == (kAXRadioButtonRole as String) {
                    score += 15
                }
                return score >= 70 ? (snapshot.element, score) : nil
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func stringAttribute(_ name: String, of element: AXUIElement) -> String {
        guard let value = attribute(name, of: element) else {
            return ""
        }
        if let string = value as? String {
            return string
        }
        return ""
    }

    private func stringListAttribute(_ name: String, of element: AXUIElement) -> [String] {
        attribute(name, of: element) as? [String] ?? []
    }

    private func booleanAttribute(_ name: String, of element: AXUIElement) -> Bool {
        attribute(name, of: element) as? Bool ?? false
    }

    private func rectAttribute(_ name: String, of element: AXUIElement) -> CGRect? {
        guard let value = attribute(name, of: element),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(
            unsafeDowncast(value, to: AXValue.self),
            .cgRect,
            &rect
        ) else {
            return nil
        }
        return rect
    }

    private func actionNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(element, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    private func attributeNames(of element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success else {
            return []
        }
        return names as? [String] ?? []
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
