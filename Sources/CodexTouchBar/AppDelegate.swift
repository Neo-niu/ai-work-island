import AppKit
import CodexTouchBarCore
import WidgetKit

private struct WidgetPresentationState: Equatable {
    let id: String
    let title: String
    let detail: String?
    let status: WorkItemStatus
    let startedAt: Date?
    let outputPath: String?
    let phase: String?
    let phaseIndex: Int?
    let phaseCount: Int?

    init(_ item: WorkItem) {
        id = item.id
        title = item.title
        detail = item.detail
        status = item.status
        startedAt = item.startedAt
        outputPath = item.outputPath
        phase = item.phase
        phaseIndex = item.phaseIndex
        phaseCount = item.phaseCount
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let restoreDashboardNotification = Notification.Name(
        "dev.kanyun.CodexHermesTouchBar.restoreDashboard"
    )
    private static let enabledDefaultsKey = "touchBarEnabled"
    private static let alwaysShowDefaultsKey = "touchBarAlwaysShow"
    private static let desktopPanelVisibleDefaultsKey = "desktopPanelVisible"
    private static let desktopWidgetModeDefaultsKey = "desktopWidgetMode"

    private let scanner = RolloutScanner()
    private let automationStatusScanner = AutomationStatusScanner()
    private let companyQuotaScanner = CompanyQuotaScanner()
    private let grouper = ProjectGrouper()
    private let touchBarController = TouchBarController()
    private let desktopPanelController = DesktopStatusPanelController()
    private let voiceMemoLauncher = VoiceMemoLauncher()
    private let recordingHotKey = GlobalRecordingHotKey()
    private let widgetSnapshotStore = WidgetSnapshotStore()
    private let accessibilityController = CodexAccessibilityController()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var alwaysShowMenuItem: NSMenuItem?
    private var desktopPanelMenuItem: NSMenuItem?
    private var desktopWidgetModeMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var scheduledRefreshInterval: TimeInterval?
    private var refreshInFlight = false
    private var latestGroups: [ProjectGroup]?
    private var latestThreadCount = 0
    private var latestUnreadThreadCount = 0
    private var transientStatus: (message: String, expiresAt: Date)?
    private var threadStatusCycler = ThreadStatusCycler()
    private var latestWidgetItems: [WorkItem]?
    private var latestWidgetPresentation: [WidgetPresentationState]?
    private var latestHasActiveWork = false

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

    private var isDesktopWidgetMode: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.desktopWidgetModeDefaultsKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Self.desktopWidgetModeDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.desktopWidgetModeDefaultsKey)
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
        desktopPanelController.onVoiceMemoSelected = { [weak self] in
            self?.startVoiceMemoRecording()
        }
        desktopPanelController.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.isDesktopPanelVisible = visible
            self.desktopPanelMenuItem?.state = visible ? .on : .off
            self.updateRefreshSchedule()
        }
        desktopPanelController.setDisplayMode(isDesktopWidgetMode ? .desktopWidget : .floating)

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
            desktopPanelController.show()
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

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: {
            $0.scheme == WidgetStatusConfiguration.urlScheme
        }) else {
            return
        }
        if url.host == "record" {
            startVoiceMemoRecording()
            return
        }
        if url.host == "refresh" {
            requestRefresh()
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetStatusConfiguration.kind)
            showTransientStatus("正在刷新桌面小组件")
            return
        }
        isDesktopPanelVisible = true
        desktopPanelMenuItem?.state = .on
        desktopPanelController.show()
        updateRefreshSchedule()
        requestRefresh()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.and.hand.point.up.left.fill",
                accessibilityDescription: "Codex Touch Bar"
            ) ?? NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "Codex Touch Bar")
            button.image?.isTemplate = true
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

        let desktopWidgetModeMenuItem = NSMenuItem(
            title: "桌面小组件模式（窗口后方）",
            action: #selector(toggleDesktopWidgetMode(_:)),
            keyEquivalent: ""
        )
        desktopWidgetModeMenuItem.target = self
        desktopWidgetModeMenuItem.state = isDesktopWidgetMode ? .on : .off
        menu.addItem(desktopWidgetModeMenuItem)

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

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openCodexItem = NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o")
        openCodexItem.target = self
        menu.addItem(openCodexItem)

        let openHermesItem = NSMenuItem(title: "打开 Hermes", action: #selector(openHermes), keyEquivalent: "h")
        openHermesItem.target = self
        menu.addItem(openHermesItem)

        menu.addItem(.separator())
        let restartItem = NSMenuItem(title: "重启应用", action: #selector(restartApplication), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "退出 Codex Hermes Touch Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.statusMenuItem = statusMenuItem
        self.enabledMenuItem = enabledMenuItem
        self.alwaysShowMenuItem = alwaysShowMenuItem
        self.desktopPanelMenuItem = desktopPanelMenuItem
        self.desktopWidgetModeMenuItem = desktopWidgetModeMenuItem

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
        desktopPanelController.update(snapshot: WorkStatusSnapshot(
            items: workItems,
            automationIssues: automationResult.issues,
            codexShortTermLimit: shortTermLimit,
            codexWeeklyLimit: weeklyLimit,
            companyQuota: companyQuota
        ))
        publishWidgetSnapshotIfNeeded(items: workItems)
        updateStatusText()
    }

    private func publishWidgetSnapshotIfNeeded(items: [WorkItem]) {
        guard latestWidgetItems != items else { return }
        do {
            try widgetSnapshotStore.write(WidgetStatusSnapshot(items: items))
            latestWidgetItems = items
            let presentation = items.map(WidgetPresentationState.init)
            if presentation != latestWidgetPresentation {
                latestWidgetPresentation = presentation
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetStatusConfiguration.kind)
            }
        } catch {
            showTransientStatus("无法更新系统小组件：\(error.localizedDescription)", duration: 15)
        }
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

    @objc private func refreshNow() {
        requestRefresh()
        updatePresentation()
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

    @objc private func toggleDesktopWidgetMode(_ sender: NSMenuItem) {
        isDesktopWidgetMode.toggle()
        sender.state = isDesktopWidgetMode ? .on : .off
        desktopPanelController.setDisplayMode(isDesktopWidgetMode ? .desktopWidget : .floating)
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

    @objc private func openCodex() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    @objc private func openHermes() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/Hermes.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
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
