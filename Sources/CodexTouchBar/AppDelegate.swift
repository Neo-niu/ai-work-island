import AppKit
import CodexTouchBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let restoreDashboardNotification = Notification.Name(
        "dev.kanyun.CodexHermesTouchBar.restoreDashboard"
    )
    private static let enabledDefaultsKey = "touchBarEnabled"
    private static let alwaysShowDefaultsKey = "touchBarAlwaysShow"
    private static let desktopPanelVisibleDefaultsKey = "desktopPanelVisible"
    private static let backgroundPanelModeDefaultsKey = "backgroundPanelMode"

    private let scanner = RolloutScanner()
    private let automationStatusScanner = AutomationStatusScanner()
    private let companyQuotaScanner = CompanyQuotaScanner()
    private let grouper = ProjectGrouper()
    private let touchBarController = TouchBarController()
    private let desktopPanelController = DesktopStatusPanelController()
    private let voiceMemoLauncher = VoiceMemoLauncher()
    private let recordingHotKey = GlobalRecordingHotKey()
    private let accessibilityController = CodexAccessibilityController()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var alwaysShowMenuItem: NSMenuItem?
    private var desktopPanelMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var scheduledRefreshInterval: TimeInterval?
    private var refreshInFlight = false
    private var latestGroups: [ProjectGroup]?
    private var latestThreadCount = 0
    private var latestUnreadThreadCount = 0
    private var transientStatus: (message: String, expiresAt: Date)?
    private var threadStatusCycler = ThreadStatusCycler()
    private var latestHasActiveWork = false
    private var conversationInFlight = false
    private var cardConversationsInFlight: Set<String> = []

    private var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.enabledDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledDefaultsKey)
        }
    }

    private var alwaysShow: Bool {
        get { UserDefaults.standard.bool(forKey: Self.alwaysShowDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.alwaysShowDefaultsKey) }
    }

    private var isDesktopPanelVisible: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.desktopPanelVisibleDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.desktopPanelVisibleDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.desktopPanelVisibleDefaultsKey)
        }
    }

    private var isBackgroundPanelMode: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.backgroundPanelModeDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.backgroundPanelModeDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.backgroundPanelModeDefaultsKey)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runningPIDs = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).map(\.processIdentifier)
        if SingleInstancePolicy.shouldTerminate(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            runningPIDs: runningPIDs
        ) {
            DistributedNotificationCenter.default().post(
                name: Self.restoreDashboardNotification,
                object: nil,
                userInfo: nil
            )
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        // Closing the dashboard hides it only for the current run. A fresh app
        // launch should always restore the primary task dashboard.
        isDesktopPanelVisible = true
        configureStatusItem()
        LaunchAtLoginController.registerIfNeeded()
        recordingHotKey.onPressed = { [weak self] in
            self?.startVoiceMemoRecording()
        }
        do {
            try recordingHotKey.register()
        } catch {
            showTransientStatus(error.localizedDescription, duration: 15)
        }

        touchBarController.onProcessingSelected = { [weak self] in
            self?.openNextThread(category: .processing)
        }
        touchBarController.onUnreadSelected = { [weak self] in
            self?.openNextThread(category: .unread)
        }
        desktopPanelController.onItemSelected = { [weak self] item in
            self?.openWorkItem(item)
        }
        desktopPanelController.onItemDetailsSelected = { [weak self] item in
            self?.showWorkItemDetails(item)
        }
        desktopPanelController.onItemOutputSelected = { [weak self] item in
            self?.openWorkItemOutput(item)
        }
        desktopPanelController.onCodexPromptSubmitted = { [weak self] itemID, prompt in
            self?.submitCodexCardPrompt(itemID: itemID, prompt: prompt)
        }
        desktopPanelController.onNewConversationSubmitted = { [weak self] prompt in
            self?.submitNewConversation(prompt: prompt)
        }
        desktopPanelController.onNewConversationDirectorySelected = { [weak self] in
            self?.chooseProjectForNewConversation()
        }
        desktopPanelController.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.isDesktopPanelVisible = visible
            self.desktopPanelMenuItem?.state = visible ? .on : .off
            self.updateRefreshSchedule()
        }
        desktopPanelController.setDisplayMode(isBackgroundPanelMode ? .background : .floating)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(restoreDashboardFromExplicitOpen),
            name: Self.restoreDashboardNotification,
            object: nil
        )

        updateRefreshSchedule()
        requestRefresh()
        updatePresentation()
        if isDesktopPanelVisible {
            desktopPanelController.showCollapsed()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        recordingHotKey.unregister()
        touchBarController.dismiss()
        desktopPanelController.hide()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusItemIconRenderer.makeImage()
        }

        let menu = NSMenu()
        let statusMenuItem = NSMenuItem(title: "正在读取 Codex 状态…", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        let enabledMenuItem = NSMenuItem(
            title: "启用 Touch Bar 仪表盘",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledMenuItem.target = self
        enabledMenuItem.state = isEnabled ? .on : .off
        menu.addItem(enabledMenuItem)

        let alwaysShowMenuItem = NSMenuItem(
            title: "始终显示（所有应用）",
            action: #selector(toggleAlwaysShow(_:)),
            keyEquivalent: ""
        )
        alwaysShowMenuItem.target = self
        alwaysShowMenuItem.state = alwaysShow ? .on : .off
        menu.addItem(alwaysShowMenuItem)

        let desktopPanelMenuItem = NSMenuItem(
            title: "显示桌面状态面板",
            action: #selector(toggleDesktopPanel(_:)),
            keyEquivalent: ""
        )
        desktopPanelMenuItem.target = self
        desktopPanelMenuItem.state = isDesktopPanelVisible ? .on : .off
        menu.addItem(desktopPanelMenuItem)

        let backgroundPanelModeMenuItem = NSMenuItem(
            title: "置于普通窗口后方",
            action: #selector(toggleBackgroundPanelMode(_:)),
            keyEquivalent: ""
        )
        backgroundPanelModeMenuItem.target = self
        backgroundPanelModeMenuItem.state = isBackgroundPanelMode ? .on : .off
        menu.addItem(backgroundPanelModeMenuItem)

        let openStatusDirectoryItem = NSMenuItem(
            title: "打开自动化状态目录",
            action: #selector(openAutomationStatusDirectory),
            keyEquivalent: ""
        )
        openStatusDirectoryItem.target = self
        menu.addItem(openStatusDirectoryItem)

        let startVoiceMemoItem = NSMenuItem(
            title: "开始语音备忘录（全局 ⌥⌘R）",
            action: #selector(startVoiceMemoFromMenu),
            keyEquivalent: "r"
        )
        startVoiceMemoItem.keyEquivalentModifierMask = [.command, .option]
        startVoiceMemoItem.target = self
        menu.addItem(startVoiceMemoItem)

        menu.addItem(.separator())
        let restartItem = NSMenuItem(title: "重启应用", action: #selector(restartApplication), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "退出 AI 工作岛", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.statusMenuItem = statusMenuItem
        self.enabledMenuItem = enabledMenuItem
        self.alwaysShowMenuItem = alwaysShowMenuItem
        self.desktopPanelMenuItem = desktopPanelMenuItem

        if !touchBarController.isAvailable {
            statusMenuItem.title = "当前系统不支持 Touch Bar 常驻接口"
            enabledMenuItem.isEnabled = false
            alwaysShowMenuItem.isEnabled = false
        }
    }

    private func requestRefresh() {
        guard !refreshInFlight else {
            return
        }
        refreshInFlight = true

        Task { [weak self, scanner, automationStatusScanner, companyQuotaScanner, grouper] in
            let snapshot = await scanner.scanSnapshot()
            let automationResult = automationStatusScanner.scan()
            let companyQuota = await companyQuotaScanner.scanIfNeeded()
            guard let self else {
                return
            }
            let selectedProjectName = self.isCodexFrontmost
                ? self.accessibilityController.selectedSidebarProjectName()
                : nil
            let groups = grouper.groups(
                from: snapshot.threads,
                selectedProjectRoots: snapshot.selectedProjectRoots,
                selectedProjectName: selectedProjectName
            )
            self.apply(
                groups: groups,
                shortTermLimit: snapshot.shortTermLimit,
                weeklyLimit: snapshot.weeklyLimit,
                companyQuota: companyQuota,
                automationResult: automationResult
            )
            self.refreshInFlight = false
        }
    }

    private func apply(
        groups: [ProjectGroup],
        shortTermLimit: WeeklyLimitUsage?,
        weeklyLimit: WeeklyLimitUsage?,
        companyQuota: CompanyModelQuota?,
        automationResult: AutomationScanResult
    ) {
        touchBarController.update(groups: groups)
        if RefreshPolicy.shouldApply(previous: latestGroups, next: groups) {
            latestGroups = groups
            latestThreadCount = groups.reduce(0) {
                $0 + $1.threads.filter(\.isActive).count
            }
            latestUnreadThreadCount = groups.reduce(0) {
                $0 + $1.threads.filter(\.isUnread).count
            }
        }
        touchBarController.showCodexLimits(shortTerm: shortTermLimit, weekly: weeklyLimit)
        touchBarController.showCompanyQuota(companyQuota)
        let codexItems = WorkStatusHub.codexItems(from: groups)
        let workItems = WorkStatusHub.merge(codex: codexItems, automation: automationResult.items)
        let hasActiveWork = workItems.contains { $0.status.isActiveWork }
        if latestHasActiveWork != hasActiveWork {
            latestHasActiveWork = hasActiveWork
            updateRefreshSchedule()
        }
        desktopPanelController.updateCodexCardResults(from: groups)
        desktopPanelController.update(snapshot: WorkStatusSnapshot(
            items: workItems,
            automationIssues: automationResult.issues,
            codexShortTermLimit: shortTermLimit,
            codexWeeklyLimit: weeklyLimit,
            companyQuota: companyQuota
        ))
        updateStatusText()
    }

    private func updateStatusText() {
        if let transientStatus, transientStatus.expiresAt > Date() {
            statusMenuItem?.title = transientStatus.message
            return
        }
        transientStatus = nil

        switch (latestThreadCount, latestUnreadThreadCount) {
        case (0, 0):
            statusMenuItem?.title = "Codex 空闲"
        case (_, 0):
            statusMenuItem?.title = "处理中 \(latestThreadCount)"
        case (0, _):
            statusMenuItem?.title = "待读 \(latestUnreadThreadCount)"
        default:
            statusMenuItem?.title = "处理中 \(latestThreadCount) · 待读 \(latestUnreadThreadCount)"
        }
    }

    private func updatePresentation() {
        if shouldPresentDashboard && touchBarController.isAvailable {
            _ = touchBarController.present()
        } else {
            touchBarController.dismiss()
        }
    }

    private var isCodexFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.codexBundleIdentifier
    }

    private var shouldPresentDashboard: Bool {
        isEnabled && (alwaysShow || isCodexFrontmost)
    }

    private func updateRefreshSchedule() {
        let shouldRefresh = shouldPresentDashboard || isDesktopPanelVisible
        let interval = RefreshPolicy.pollInterval(
            isDashboardVisible: shouldRefresh,
            hasActiveWork: latestHasActiveWork
        )
        guard scheduledRefreshInterval != interval else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        scheduledRefreshInterval = interval
        let timer = Timer(
            timeInterval: interval,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: RefreshPolicy.timerRunLoopMode)
        refreshTimer = timer
    }

    private func openNextThread(category: ThreadStatusCategory) {
        guard let latestGroups,
              let thread = threadStatusCycler.nextThread(in: latestGroups, category: category) else {
            showTransientStatus(category == .processing ? "当前没有处理中的会话" : "当前没有待读会话")
            return
        }
        openThread(
            thread,
            successMessage: category == .processing ? "已打开处理中的会话" : "已打开待读会话"
        )
    }

    private func openThread(
        _ thread: ActiveThread,
        successMessage: String
    ) {
        guard let url = URL(string: "codex://threads/\(thread.id)") else {
            showTransientStatus("无法生成目标会话链接")
            return
        }
        guard NSWorkspace.shared.open(url) else {
            showTransientStatus("Codex 未接受会话跳转")
            return
        }
        showTransientStatus(successMessage)
    }

    private func openWorkItem(_ item: WorkItem) {
        if item.status.requiresAttention {
            showWorkItemIssue(item)
            return
        }
        if item.id.hasPrefix("codex:"),
           let thread = latestGroups?.flatMap(\.threads).first(where: {
               "codex:\($0.id)" == item.id
           }) {
            openThread(
                thread,
                successMessage: "已打开 Codex 会话"
            )
            return
        }
        if let rawURL = item.openURL, let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            return
        }
        if let outputPath = item.outputPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
            return
        }
        showTransientStatus("该任务没有可打开的产出")
    }

    private func showWorkItemIssue(_ item: WorkItem) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\(item.displayTitle) · \(item.status == .stale ? "状态失联" : "运行异常")"
        alert.informativeText = item.displayDetail.isEmpty
            ? "没有提供更多异常信息。"
            : item.displayDetail
        alert.addButton(withTitle: "关闭")

        let destination: URL?
        let actionTitle: String?
        if let rawURL = item.openURL, let url = URL(string: rawURL) {
            destination = url
            actionTitle = "打开详情"
        } else if let outputPath = item.outputPath {
            destination = URL(fileURLWithPath: outputPath)
            actionTitle = "打开产出"
        } else {
            destination = nil
            actionTitle = nil
        }
        if let actionTitle {
            alert.addButton(withTitle: actionTitle)
        }

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        if alert.runModal() == .alertSecondButtonReturn, let destination {
            NSWorkspace.shared.open(destination)
        }
    }

    private func showWorkItemDetails(_ item: WorkItem) {
        if item.status.requiresAttention {
            showWorkItemIssue(item)
            return
        }
        let alert = NSAlert()
        alert.messageText = item.displayTitle
        let phase = item.phase.map { "当前阶段：\($0)\n" } ?? ""
        alert.informativeText = "\(phase)\(item.displayDetail)"
        alert.addButton(withTitle: "关闭")
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        alert.runModal()
    }

    private func openWorkItemOutput(_ item: WorkItem) {
        guard let outputPath = item.outputPath else {
            showTransientStatus("该任务没有可打开的产出")
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
    }

    private func showSettingError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        showTransientStatus(message, duration: 15)
        NSSound.beep()
    }

    private func showTransientStatus(_ message: String, duration: TimeInterval = 6) {
        transientStatus = (message, Date().addingTimeInterval(duration))
        statusMenuItem?.title = message
    }

    private var newConversationProjectURL: URL {
        if let storedPath = UserDefaults.standard.string(forKey: "newConversationProjectPath"),
           FileManager.default.fileExists(atPath: storedPath) {
            return URL(fileURLWithPath: storedPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private func chooseProjectForNewConversation() {
        guard !conversationInFlight else {
            showTransientStatus("新会话正在创建")
            return
        }
        let chooser = NSOpenPanel()
        chooser.title = "选择新任务工作目录"
        chooser.prompt = "选择项目"
        chooser.message = "后续直接输入的新任务都会使用此目录。"
        chooser.canChooseFiles = false
        chooser.canChooseDirectories = true
        chooser.allowsMultipleSelection = false
        chooser.canCreateDirectories = true
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        guard chooser.runModal() == .OK, let projectURL = chooser.url else { return }
        UserDefaults.standard.set(projectURL.path, forKey: "newConversationProjectPath")
        showTransientStatus("新任务将创建在 \(projectURL.lastPathComponent)")
    }

    private func submitNewConversation(prompt: String, projectURL: URL? = nil) {
        guard !conversationInFlight else {
            showTransientStatus("新会话正在创建")
            return
        }
        let projectURL = projectURL ?? newConversationProjectURL
        conversationInFlight = true
        desktopPanelController.setNewConversationBusy(true)
        showTransientStatus("正在创建 \(projectURL.lastPathComponent) 会话")
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await CodexConversationBridge.send(
                    prompt: prompt,
                    route: .new(cwd: projectURL)
                )
                showTransientStatus("\(projectURL.lastPathComponent) 会话已创建")
                requestRefresh()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showTransientStatus(message, duration: 15)
                NSSound.beep()
            }
            conversationInFlight = false
            desktopPanelController.setNewConversationBusy(false)
        }
    }

    private func submitCodexCardPrompt(itemID: String, prompt: String) {
        guard !cardConversationsInFlight.contains(itemID) else {
            desktopPanelController.updateCodexCardStatus(
                itemID: itemID,
                text: "上一条指令仍在发送",
                isBusy: true
            )
            return
        }
        let threadID = String(itemID.dropFirst("codex:".count))
        guard let thread = latestGroups?.flatMap(\.threads).first(where: { $0.id == threadID }) else {
            desktopPanelController.updateCodexCardStatus(itemID: itemID, text: "该项目会话当前不可用")
            NSSound.beep()
            return
        }

        cardConversationsInFlight.insert(itemID)
        desktopPanelController.updateCodexCardStatus(
            itemID: itemID,
            text: "正在续接该项目…",
            isBusy: true
        )
        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await CodexConversationBridge.send(
                    prompt: prompt,
                    route: .desktopThread(
                        threadID: thread.id,
                        cwd: thread.cwd,
                        isActive: thread.isActive
                    )
                )
                desktopPanelController.updateCodexCardStatus(
                    itemID: itemID,
                    text: Self.compactConversationText(result.assistantText)
                )
                showTransientStatus("已续接 \(thread.cwd.lastPathComponent)")
                requestRefresh()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                desktopPanelController.updateCodexCardStatus(itemID: itemID, text: message)
                showTransientStatus(message, duration: 15)
                NSSound.beep()
            }
            cardConversationsInFlight.remove(itemID)
        }
    }

    private static func compactConversationText(_ text: String) -> String {
        let compact = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard compact.count > 120 else { return compact }
        return String(compact.prefix(119)) + "…"
    }

    private func startVoiceMemoRecording() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await voiceMemoLauncher.start()
                showTransientStatus("录音已开始；完成后将自动转写")
            } catch {
                if case VoiceMemoLauncher.LauncherError.accessibilityRequired = error {
                    _ = accessibilityController.requestAccessibilityAccess()
                }
                showSettingError(error)
            }
        }
    }

    @objc private func startVoiceMemoFromMenu() {
        startVoiceMemoRecording()
    }

    @objc private func frontmostApplicationChanged(_ notification: Notification) {
        updateRefreshSchedule()
        if shouldPresentDashboard {
            requestRefresh()
        }
        updatePresentation()
    }

    @objc private func refreshTimerFired() {
        requestRefresh()
    }

    @objc private func restoreDashboardFromExplicitOpen() {
        isDesktopPanelVisible = true
        desktopPanelMenuItem?.state = .on
        desktopPanelController.show()
        updateRefreshSchedule()
        requestRefresh()
        if isEnabled, touchBarController.isAvailable {
            _ = touchBarController.restorePresentation()
        }
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        sender.state = isEnabled ? .on : .off
        updateRefreshSchedule()
        if shouldPresentDashboard {
            requestRefresh()
        }
        updatePresentation()
    }

    @objc private func toggleAlwaysShow(_ sender: NSMenuItem) {
        alwaysShow.toggle()
        sender.state = alwaysShow ? .on : .off
        if alwaysShow, !isEnabled {
            isEnabled = true
            enabledMenuItem?.state = .on
        }
        updateRefreshSchedule()
        if shouldPresentDashboard {
            requestRefresh()
        }
        updatePresentation()
    }

    @objc private func toggleDesktopPanel(_ sender: NSMenuItem) {
        isDesktopPanelVisible.toggle()
        sender.state = isDesktopPanelVisible ? .on : .off
        if isDesktopPanelVisible {
            desktopPanelController.show()
            requestRefresh()
        } else {
            desktopPanelController.hide()
        }
        updateRefreshSchedule()
    }

    @objc private func toggleBackgroundPanelMode(_ sender: NSMenuItem) {
        isBackgroundPanelMode.toggle()
        sender.state = isBackgroundPanelMode ? .on : .off
        desktopPanelController.setDisplayMode(isBackgroundPanelMode ? .background : .floating)
        if isDesktopPanelVisible {
            desktopPanelController.show()
        }
    }

    @objc private func openAutomationStatusDirectory() {
        let directory = automationStatusScanner.statusDirectory
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(directory)
        } catch {
            showTransientStatus("无法打开状态目录：\(error.localizedDescription)", duration: 15)
        }
    }

    @objc private func restartApplication() {
        let bundlePath = Bundle.main.bundlePath
        let relauncher = Process()
        relauncher.executableURL = URL(fileURLWithPath: "/bin/sh")
        relauncher.arguments = [
            "-c",
            "sleep 0.5; exec /usr/bin/open -n \"$1\"",
            "codex-touch-bar-relauncher",
            bundlePath,
        ]

        do {
            try relauncher.run()
            NSApp.terminate(nil)
        } catch {
            showTransientStatus("重启失败：\(error.localizedDescription)", duration: 15)
            NSSound.beep()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
