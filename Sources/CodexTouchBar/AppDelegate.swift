import AppKit
import CodexTouchBarCore
import UserNotifications

enum CodexThreadOpeningPolicy {
    static func requiresWorkIslandTransfer(
        threadID: String,
        retainedWorkIslandThreadIDs: Set<String>
    ) -> Bool {
        retainedWorkIslandThreadIDs.contains(threadID)
    }

    static func shouldHideOptimistically(isOwnershipTransfer: Bool) -> Bool {
        !isOwnershipTransfer
    }
}

enum WorkItemPrimaryAction: Equatable {
    case codexThread
    case issue
    case destination

    static func resolve(_ item: WorkItem) -> Self {
        if item.id.hasPrefix("codex:") { return .codexThread }
        if item.status.requiresAttention { return .issue }
        return .destination
    }
}

enum AppReopenPolicy {
    /// Repeated LaunchServices opens can come from background tooling or system
    /// services. The island is restored only by its capsule or menu actions.
    static let shouldRestoreDashboard = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let enabledDefaultsKey = "touchBarEnabled"
    private static let alwaysShowDefaultsKey = "touchBarAlwaysShow"
    private static let desktopPanelVisibleDefaultsKey = "desktopPanelVisible"
    private static let backgroundPanelModeDefaultsKey = "backgroundPanelMode"
    private static let desktopContentModeDefaultsKey = "desktopContentMode"
    private static let silentModeDefaultsKey = "silentMode"
    private static let appearanceModeDefaultsKey = "appearanceMode"
    private static let recordingReminderCategory = "voice-memo-silence-reminder"
    private static let finishRecordingAction = "finish-and-keep-voice-memo"
    private static let continueRecordingAction = "continue-voice-memo"
    private static let meetingTodoCategory = "meeting-todo-confirmation"
    private static let keepMeetingTodoAction = "keep-meeting-todo"
    private static let deleteMeetingTodoAction = "delete-meeting-todo"

    private let scanner = RolloutScanner()
    private let automationStatusScanner = AutomationStatusScanner()
    private let meetingTodoQueue = MeetingTodoConfirmationQueue()
    private let meetingReminderWriter = MeetingReminderWriter()
    private let companyQuotaScanner = CompanyQuotaScanner()
    private let grouper = ProjectGrouper()
    private let touchBarController = TouchBarController()
    private let desktopPanelController = DesktopStatusPanelController()
    private let voiceMemoLauncher = VoiceMemoLauncher()
    private let voiceMemoGuardian = VoiceMemoGuardian()
    private let recordingHotKey = GlobalRecordingHotKey()
    private let accessibilityController = CodexAccessibilityController()
    private let updateController = GitHubUpdateController(
        repository: "Neo-niu/ai-work-island",
        appName: "AI工作岛"
    )
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var alwaysShowMenuItem: NSMenuItem?
    private var desktopPanelMenuItem: NSMenuItem?
    private var cleanContentModeMenuItem: NSMenuItem?
    private var detailedContentModeMenuItem: NSMenuItem?
    private var silentModeMenuItem: NSMenuItem?
    private var appearanceMenuItems: [AppAppearanceMode: NSMenuItem] = [:]
    private var finishVoiceMemoMenuItem: NSMenuItem?
    private var continueVoiceMemoMenuItem: NSMenuItem?
    private var recordingHotKeyMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var companyQuotaTimer: Timer?
    private var scheduledRefreshInterval: TimeInterval?
    private var refreshInFlight = false
    private var refreshPending = false
    private var companyQuotaRefreshInFlight = false
    private var latestCompanyQuota: CompanyModelQuota?
    private var optimisticallyViewedAtByThreadID: [String: Date] = [:]
    private var latestGroups: [ProjectGroup]?
    private var latestThreadCount = 0
    private var latestUnreadThreadCount = 0
    private var transientStatus: (message: String, expiresAt: Date)?
    private var threadStatusCycler = ThreadStatusCycler()
    private var latestHasActiveWork = false
    private var conversationInFlight = false
    private var pendingCreatedThreads: [String: PendingCreatedThread] = [:]
    private var cardConversationsInFlight: Set<String> = []
    private var ownershipTransfersInFlight: Set<String> = []
    private var pendingRestartRecoveryTransferThreadID: String?
    private var voiceMemoGuardianState: VoiceMemoGuardianState?
    private var didRequestRecordingNotificationAuthorization = false
    private var recordingNotificationsAuthorized = false
    private var notifiedMeetingTodoIDs: Set<String> = []
    private var meetingTodoAlertVisible = false
    private var voiceMemoRenameInFlight = false
    private var lastVoiceMemoRenameAttempt = Date.distantPast

    private var isSilentMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.silentModeDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.silentModeDefaultsKey) }
    }

    private var appearanceMode: AppAppearanceMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Self.appearanceModeDefaultsKey) else {
                return .system
            }
            return AppAppearanceMode(rawValue: raw) ?? .system
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Self.appearanceModeDefaultsKey) }
    }

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
                return false
            }
            return UserDefaults.standard.bool(forKey: Self.backgroundPanelModeDefaultsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.backgroundPanelModeDefaultsKey)
        }
    }

    private var desktopContentMode: DesktopContentMode {
        get {
            guard let rawValue = UserDefaults.standard.string(
                forKey: Self.desktopContentModeDefaultsKey
            ) else { return .clean }
            return DesktopContentMode(rawValue: rawValue) ?? .clean
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.desktopContentModeDefaultsKey)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Closing the dashboard hides it only for the current run. A fresh app
        // launch should always restore the primary task dashboard.
        isDesktopPanelVisible = true
        configureStatusItem()
        configureRecordingNotifications()
        LaunchAtLoginController.registerIfNeeded()
        // Voice Memo recording state and the explicit “finish and keep” action
        // are exposed only through macOS Accessibility.
        _ = accessibilityController.requestAccessibilityAccess()
        recordingHotKey.onPressed = { [weak self] in
            self?.performRecordingHotKeyAction()
        }
        voiceMemoGuardian.onStateChanged = { [weak self] state in
            guard let self else { return }
            voiceMemoGuardianState = state
            desktopPanelController.updateRecordingGuardian(state)
            updateRecordingHotKeyMenuItem(isRecording: state != nil)
            finishVoiceMemoMenuItem?.isHidden = state == nil
            continueVoiceMemoMenuItem?.isHidden = state?.phase != .silence
            if state != nil { requestRecordingNotificationAuthorizationIfNeeded() }
        }
        voiceMemoGuardian.onSilenceReminder = { [weak self] state in
            self?.showRecordingSilenceReminder(state)
        }
        voiceMemoGuardian.onWaveformLevelChanged = { [weak self] level in
            self?.desktopPanelController.updateRecordingWaveformLevel(level)
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
        desktopPanelController.onItemAcknowledged = { [weak self] item in
            guard let self,
                  item.id.hasPrefix("codex:") else { return }
            self.acknowledgeCodexThreads([
                String(item.id.dropFirst("codex:".count)),
            ])
        }
        desktopPanelController.onAllWaitingAcknowledged = { [weak self] in
            guard let self else { return }
            let threadIDs = (self.latestGroups ?? []).flatMap(\.threads)
                .filter(\.isUnread)
                .map(\.id)
            guard !threadIDs.isEmpty else {
                self.showTransientStatus("当前没有待读会话")
                return
            }
            self.acknowledgeCodexThreads(threadIDs)
        }
        desktopPanelController.onCodexTransferSelected = { [weak self] item in
            self?.transferWorkItemToCodex(item)
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
        desktopPanelController.onStopRecordingSelected = { [weak self] in
            self?.finishVoiceMemoRecording()
        }
        desktopPanelController.onVisibilityChanged = { [weak self] visible in
            guard let self else { return }
            self.isDesktopPanelVisible = visible
            self.desktopPanelMenuItem?.state = visible ? .on : .off
            self.updateRefreshSchedule()
        }
        desktopPanelController.setDisplayMode(isBackgroundPanelMode ? .background : .floating)
        desktopPanelController.setContentMode(desktopContentMode)
        desktopPanelController.suppressesAutomaticReveals = isSilentMode
        desktopPanelController.setAppearanceMode(appearanceMode)

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        updateRefreshSchedule()
        requestRefresh()
        requestRecordingNotificationAuthorizationIfNeeded()
        processMeetingTodoConfirmations()
        startCompanyQuotaRefreshSchedule()
        requestCompanyQuotaRefresh()
        updatePresentation()
        let completionUIReviewMode = DesktopCompletionUIReviewMode(
            arguments: ProcessInfo.processInfo.arguments
        )
        if completionUIReviewMode != .disabled {
            desktopPanelController.startCompletionUIReview(completionUIReviewMode)
        } else if ProcessInfo.processInfo.arguments.contains("--ui-review-panel") {
            desktopPanelController.show()
        } else if isDesktopPanelVisible {
            desktopPanelController.showCollapsed()
        }
        voiceMemoGuardian.start()
        if ProcessInfo.processInfo.arguments.contains("--ui-review-recording-waveform") {
            desktopPanelController.updateRecordingGuardian(
                VoiceMemoGuardianState(phase: .recording, startedAt: Date(), silentSince: nil)
            )
            desktopPanelController.updateRecordingWaveformLevel(0.72)
        }
        updateController.scheduleAutomaticCheck()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        AppReopenPolicy.shouldRestoreDashboard
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        companyQuotaTimer?.invalidate()
        voiceMemoGuardian.stop()
        recordingHotKey.unregister()
        touchBarController.dismiss()
        desktopPanelController.hide()
        updateController.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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

        let silentModeMenuItem = NSMenuItem(
            title: "静默运行（开会 / 投屏）",
            action: #selector(toggleSilentMode(_:)),
            keyEquivalent: ""
        )
        silentModeMenuItem.target = self
        silentModeMenuItem.state = isSilentMode ? .on : .off
        menu.addItem(silentModeMenuItem)

        let appearanceItem = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "外观")
        for mode in AppAppearanceMode.allCases {
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(selectAppearanceMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = appearanceMode == mode ? .on : .off
            appearanceMenu.addItem(item)
            appearanceMenuItems[mode] = item
        }
        appearanceItem.submenu = appearanceMenu
        menu.addItem(appearanceItem)

        let contentModeItem = NSMenuItem(title: "任务进度显示", action: nil, keyEquivalent: "")
        let contentModeMenu = NSMenu(title: "任务进度显示")
        let cleanContentModeMenuItem = NSMenuItem(
            title: DesktopContentMode.clean.title,
            action: #selector(selectCleanContentMode),
            keyEquivalent: ""
        )
        cleanContentModeMenuItem.target = self
        cleanContentModeMenuItem.state = desktopContentMode == .clean ? .on : .off
        contentModeMenu.addItem(cleanContentModeMenuItem)
        let detailedContentModeMenuItem = NSMenuItem(
            title: DesktopContentMode.detailed.title,
            action: #selector(selectDetailedContentMode),
            keyEquivalent: ""
        )
        detailedContentModeMenuItem.target = self
        detailedContentModeMenuItem.state = desktopContentMode == .detailed ? .on : .off
        contentModeMenu.addItem(detailedContentModeMenuItem)
        contentModeItem.submenu = contentModeMenu
        menu.addItem(contentModeItem)

        let openStatusDirectoryItem = NSMenuItem(
            title: "打开自动化状态目录",
            action: #selector(openAutomationStatusDirectory),
            keyEquivalent: ""
        )
        openStatusDirectoryItem.target = self
        menu.addItem(openStatusDirectoryItem)

        let startVoiceMemoItem = NSMenuItem(
            title: "开始语音备忘录（全局 Caps Lock + R）",
            action: #selector(performRecordingHotKeyActionFromMenu),
            keyEquivalent: "r"
        )
        startVoiceMemoItem.keyEquivalentModifierMask = [.command, .option]
        startVoiceMemoItem.target = self
        menu.addItem(startVoiceMemoItem)

        let finishVoiceMemoItem = NSMenuItem(
            title: "结束当前录音并保留",
            action: #selector(finishVoiceMemoFromMenu),
            keyEquivalent: ""
        )
        finishVoiceMemoItem.target = self
        finishVoiceMemoItem.isHidden = true
        menu.addItem(finishVoiceMemoItem)

        let continueVoiceMemoItem = NSMenuItem(
            title: "继续当前录音",
            action: #selector(continueVoiceMemoFromMenu),
            keyEquivalent: ""
        )
        continueVoiceMemoItem.target = self
        continueVoiceMemoItem.isHidden = true
        menu.addItem(continueVoiceMemoItem)

        menu.addItem(.separator())
        let checkForUpdatesItem = NSMenuItem(
            title: "检查更新…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        let restartItem = NSMenuItem(title: "重启应用", action: #selector(restartApplication), keyEquivalent: "")
        restartItem.target = self
        menu.addItem(restartItem)

        let quitItem = NSMenuItem(title: "退出 AI工作岛", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.statusMenuItem = statusMenuItem
        self.enabledMenuItem = enabledMenuItem
        self.alwaysShowMenuItem = alwaysShowMenuItem
        self.desktopPanelMenuItem = desktopPanelMenuItem
        self.cleanContentModeMenuItem = cleanContentModeMenuItem
        self.detailedContentModeMenuItem = detailedContentModeMenuItem
        self.silentModeMenuItem = silentModeMenuItem
        self.finishVoiceMemoMenuItem = finishVoiceMemoItem
        self.continueVoiceMemoMenuItem = continueVoiceMemoItem
        self.recordingHotKeyMenuItem = startVoiceMemoItem

        if !touchBarController.isAvailable {
            statusMenuItem.title = "当前系统不支持 Touch Bar 常驻接口"
            enabledMenuItem.isEnabled = false
            alwaysShowMenuItem.isEnabled = false
        }
    }

    private func requestRefresh() {
        processPendingVoiceMemoRenameIfNeeded()
        guard !refreshInFlight else {
            refreshPending = true
            return
        }
        refreshInFlight = true

        Task { [weak self, scanner, automationStatusScanner, grouper] in
            let snapshot = await scanner.scanSnapshot()
            let automationResult = automationStatusScanner.scan()
            guard let self else {
                return
            }
            let selectedProjectName = self.isCodexFrontmost
                ? self.accessibilityController.selectedSidebarProjectName()
                : nil
            let continuity = CreatedThreadContinuity.reconcile(
                scannedThreads: snapshot.threads,
                pending: self.pendingCreatedThreads
            )
            self.pendingCreatedThreads = continuity.pending
            let groups = grouper.groups(
                from: continuity.threads,
                selectedProjectRoots: snapshot.selectedProjectRoots,
                selectedProjectName: selectedProjectName
            )
            self.apply(
                groups: groups,
                shortTermLimit: snapshot.shortTermLimit,
                weeklyLimit: snapshot.weeklyLimit,
                companyQuota: self.latestCompanyQuota,
                automationResult: automationResult
            )
            self.refreshInFlight = false
            if self.refreshPending {
                self.refreshPending = false
                self.requestRefresh()
            }
        }
    }

    private func processPendingVoiceMemoRenameIfNeeded() {
        guard !voiceMemoRenameInFlight,
              Date().timeIntervalSince(lastVoiceMemoRenameAttempt) >= 15 else { return }
        voiceMemoRenameInFlight = true
        lastVoiceMemoRenameAttempt = Date()
        Task { [weak self] in
            guard let self else { return }
            defer { voiceMemoRenameInFlight = false }
            do {
                if try await voiceMemoLauncher.processNextRenameRequest() {
                    showTransientStatus("已按会议内容更新录音名称")
                }
            } catch {
                // Keep the request for a later retry; minutes delivery must not be blocked.
            }
        }
    }

    private func requestCompanyQuotaRefresh() {
        guard !companyQuotaRefreshInFlight else { return }
        companyQuotaRefreshInFlight = true
        Task { [weak self, companyQuotaScanner] in
            let quota = await companyQuotaScanner.scanIfNeeded()
            guard let self else { return }
            self.companyQuotaRefreshInFlight = false
            guard self.latestCompanyQuota != quota else { return }
            self.latestCompanyQuota = quota
            self.requestRefresh()
        }
    }

    private func startCompanyQuotaRefreshSchedule() {
        companyQuotaTimer?.invalidate()
        let timer = Timer(
            timeInterval: RefreshPolicy.companyQuotaInterval,
            target: self,
            selector: #selector(companyQuotaTimerFired),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: RefreshPolicy.timerRunLoopMode)
        companyQuotaTimer = timer
    }

    private func apply(
        groups rawGroups: [ProjectGroup],
        shortTermLimit: WeeklyLimitUsage?,
        weeklyLimit: WeeklyLimitUsage?,
        companyQuota: CompanyModelQuota?,
        automationResult: AutomationScanResult
    ) {
        let threadsByID = Dictionary(uniqueKeysWithValues: rawGroups.flatMap(\.threads).map { ($0.id, $0) })
        optimisticallyViewedAtByThreadID = optimisticallyViewedAtByThreadID.filter { threadID, viewedAt in
            guard let thread = threadsByID[threadID] else { return false }
            return thread.isUnread && thread.updatedAt <= viewedAt
        }
        let groups = ViewedThreadPresentationFilter.filtering(
            rawGroups,
            viewedAtByThreadID: optimisticallyViewedAtByThreadID
        )
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
        updateRefreshSchedule()
        processPendingRestartRecoveryTransfer(in: rawGroups)
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
        guard RefreshPolicy.shouldReplaceTimer(
            scheduledInterval: scheduledRefreshInterval,
            desiredInterval: interval,
            timerIsValid: refreshTimer?.isValid == true
        ) else { return }
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
        openThreadFromUserSelection(
            thread,
            successMessage: category == .processing ? "已打开处理中的会话" : "已打开待读会话"
        )
    }

    private func openThreadFromUserSelection(
        _ thread: ActiveThread,
        successMessage: String
    ) {
        if CodexThreadOpeningPolicy.requiresWorkIslandTransfer(
            threadID: thread.id,
            retainedWorkIslandThreadIDs: workIslandThreadIDs()
        ) {
            transferThreadToCodex(thread)
        } else {
            openThread(thread, successMessage: successMessage)
        }
    }

    private func openThread(
        _ thread: ActiveThread,
        successMessage: String,
        isOwnershipTransfer: Bool = false
    ) {
        if let title = thread.title,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let codex = NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.codexBundleIdentifier
           ).first {
            if CodexThreadOpeningPolicy.shouldHideOptimistically(
                isOwnershipTransfer: isOwnershipTransfer
            ) {
                beginOptimisticThreadView(thread.id)
            }
            codex.activate(options: [.activateIgnoringOtherApps])
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    // Navigate by stable thread ID. A title-only sidebar lookup misses
                    // newly indexed threads and cannot distinguish duplicate titles.
                    try await CodexAccessibilityController().openThread(
                        threadID: thread.id,
                        title: title
                    )
                    self.finishOpeningThread(thread.id, successMessage: successMessage)
                } catch {
                    if CodexThreadOpeningPolicy.shouldHideOptimistically(
                        isOwnershipTransfer: isOwnershipTransfer
                    ) {
                        self.cancelOptimisticThreadView(thread.id)
                    }
                    self.desktopPanelController.updateCodexCardStatus(
                        itemID: "codex:\(thread.id)",
                        text: "Codex 尚未接管该任务，请稍后重试"
                    )
                    self.showTransientStatus(
                        "会话已保留，Codex 仍在同步；请稍后从工作岛重试",
                        duration: 8
                    )
                }
            }
            return
        }
        if isOwnershipTransfer {
            desktopPanelController.updateCodexCardStatus(
                itemID: "codex:\(thread.id)",
                text: "Codex 未打开，任务仍保留在工作岛"
            )
        }
        showTransientStatus("请先打开 Codex，再从工作岛进入该会话", duration: 8)
    }

    private func finishOpeningThread(_ threadID: String, successMessage: String) {
        markThreadViewed(threadID)
        requestRefresh()
        showTransientStatus(successMessage)
    }

    private func markThreadViewed(_ threadID: String) {
        _ = markThreadsViewed([threadID])
    }

    private func acknowledgeCodexThreads(_ threadIDs: [String]) {
        guard !threadIDs.isEmpty else { return }
        guard markThreadsViewed(threadIDs) else {
            showTransientStatus("工作岛未能保存已读状态，请重试")
            return
        }
        showTransientStatus(threadIDs.count == 1 ? "已在工作岛完成并设为已读" : "已全部完成并设为已读")
    }

    private func beginOptimisticThreadView(_ threadID: String) {
        optimisticallyViewedAtByThreadID[threadID] = Date()
        applyOptimisticallyViewedThreads()
    }

    private func cancelOptimisticThreadView(_ threadID: String) {
        optimisticallyViewedAtByThreadID[threadID] = nil
        requestRefresh()
    }

    @discardableResult
    private func markThreadsViewed(_ threadIDs: [String]) -> Bool {
        guard !threadIDs.isEmpty else { return true }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Codex Hermes Touch Bar/viewed-thread-ids.json"
            )
        let viewedAt = Date()
        guard (try? ViewedThreadStore.markViewed(threadIDs: threadIDs, at: viewedAt, file: file)) != nil else {
            return false
        }
        for threadID in threadIDs { optimisticallyViewedAtByThreadID[threadID] = viewedAt }
        applyOptimisticallyViewedThreads()
        requestRefresh()
        return true
    }

    private func applyOptimisticallyViewedThreads() {
        guard let latestGroups else { return }
        let groups = ViewedThreadPresentationFilter.filtering(
            latestGroups,
            viewedAtByThreadID: optimisticallyViewedAtByThreadID
        )
        self.latestGroups = groups
        latestThreadCount = groups.reduce(0) { $0 + $1.threads.filter(\.isActive).count }
        latestUnreadThreadCount = groups.reduce(0) { $0 + $1.threads.filter(\.isUnread).count }
        touchBarController.update(groups: groups)
        desktopPanelController.removeViewedCodexItems(
            threadIDs: Set(optimisticallyViewedAtByThreadID.keys)
        )
        updateStatusText()
    }

    private func openWorkItem(_ item: WorkItem) {
        switch WorkItemPrimaryAction.resolve(item) {
        case .issue:
            showWorkItemIssue(item)
            return
        case .codexThread:
            guard let thread = latestGroups?.flatMap(\.threads).first(where: {
                "codex:\($0.id)" == item.id
            }) else {
                showTransientStatus("该任务当前无法转到 Codex")
                return
            }
            openThreadFromUserSelection(
                thread,
                successMessage: "已打开 Codex 会话"
            )
            return
        case .destination:
            break
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

    private func transferWorkItemToCodex(_ item: WorkItem) {
        guard item.id.hasPrefix("codex:"),
              let thread = latestGroups?.flatMap(\.threads).first(where: {
                  "codex:\($0.id)" == item.id
              }) else {
            showTransientStatus("该任务当前无法转到 Codex")
            return
        }
        transferThreadToCodex(thread)
    }

    private func transferThreadToCodex(_ thread: ActiveThread) {
        guard !ownershipTransfersInFlight.contains(thread.id) else {
            desktopPanelController.updateCodexCardStatus(
                itemID: "codex:\(thread.id)",
                text: "正在转移到 Codex，请勿重复操作",
                isBusy: true
            )
            return
        }
        beginWorkIslandTransfer(thread)
    }

    private func beginWorkIslandTransfer(_ thread: ActiveThread) {
        let hasInProcessOwner = CodexConversationBridge.hasInProcessOwner(threadID: thread.id)
        let hasOtherActiveThread = hasOtherActiveWorkIslandThread(excluding: thread.id)
        guard !RestartRecoveryTransferPolicy.shouldWaitForPeerTasks(
            hasInProcessOwner: hasInProcessOwner,
            hasOtherActiveWorkIslandThread: hasOtherActiveThread
        ) else {
            pendingRestartRecoveryTransferThreadID = thread.id
            let message = "其他任务完成后将自动转到 Codex"
            desktopPanelController.updateCodexCardStatus(
                itemID: "codex:\(thread.id)",
                text: message,
                isBusy: true
            )
            showTransientStatus(message, duration: 12)
            return
        }
        pendingRestartRecoveryTransferThreadID = nil
        ownershipTransfersInFlight.insert(thread.id)
        desktopPanelController.updateCodexCardStatus(
            itemID: "codex:\(thread.id)",
            text: "正在释放该线程的工作岛所有权…",
            isBusy: true
        )
        showTransientStatus("正在释放该线程的工作岛所有权…")
        Task { [weak self] in
            guard let self else { return }
            let result = await CodexConversationBridge.releaseWorkIslandOwnership(
                threadID: thread.id
            )
            ownershipTransfersInFlight.remove(thread.id)
            switch result {
            case .released, .alreadyTransferred:
                // After an app restart the original client connection is gone, so
                // unsubscribing from a recovery connection does not necessarily
                // unload the thread held by the durable App Server. When this is
                // the only remaining work-island task, stop that server before
                // dispatching the deep link so Codex can acquire the thread.
                if RestartRecoveryTransferPolicy.canStopServerBeforeOpening(
                    hasInProcessOwner: hasInProcessOwner,
                    hasOtherActiveWorkIslandThread: hasOtherActiveThread
                ) {
                    DurableCodexAppServer.stop()
                }
                desktopPanelController.updateCodexCardStatus(
                    itemID: "codex:\(thread.id)",
                    text: "工作岛已释放，正在转到 Codex…",
                    isBusy: true
                )
                openThread(
                    thread,
                    successMessage: "已转到 Codex",
                    isOwnershipTransfer: true
                )
            case let .failed(message):
                desktopPanelController.updateCodexCardStatus(
                    itemID: "codex:\(thread.id)",
                    text: message
                )
                showTransientStatus(message, duration: 12)
                NSSound.beep()
            }
        }
    }

    private func processPendingRestartRecoveryTransfer(in groups: [ProjectGroup]) {
        guard let threadID = pendingRestartRecoveryTransferThreadID,
              !ownershipTransfersInFlight.contains(threadID),
              let thread = groups.lazy.flatMap(\.threads).first(where: { $0.id == threadID }) else {
            return
        }
        guard !hasOtherActiveWorkIslandThread(excluding: threadID) else {
            desktopPanelController.updateCodexCardStatus(
                itemID: "codex:\(threadID)",
                text: "其他任务完成后将自动转到 Codex",
                isBusy: true
            )
            return
        }
        pendingRestartRecoveryTransferThreadID = nil
        beginWorkIslandTransfer(thread)
    }

    private func hasOtherActiveWorkIslandThread(excluding threadID: String) -> Bool {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Codex Hermes Touch Bar/work-island-thread-ids.json"
            )
        let retained = workIslandThreadIDs(file: file)
        return latestGroups?.lazy.flatMap(\.threads).contains(where: {
            $0.id != threadID && $0.isActive && retained.contains($0.id)
        }) == true
    }

    private func workIslandThreadIDs(file: URL? = nil) -> Set<String> {
        let resolvedFile = file ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Codex Hermes Touch Bar/work-island-thread-ids.json"
            )
        guard let data = try? Data(contentsOf: resolvedFile),
              let ids = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return Set(ids)
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

    private func submitNewConversation(prompt: CodexPrompt, projectURL: URL? = nil) {
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
                let result = try await CodexConversationBridge.send(
                    prompt: prompt,
                    route: .new(cwd: projectURL)
                )
                let now = Date()
                let title = prompt.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallback = ActiveThread(
                    id: result.threadID,
                    title: title.isEmpty ? "图片任务" : title,
                    cwd: projectURL,
                    startedAt: now,
                    updatedAt: now
                )
                pendingCreatedThreads[result.threadID] = PendingCreatedThread(
                    thread: fallback,
                    expiresAt: now.addingTimeInterval(30 * 60)
                )
                showTransientStatus("\(projectURL.lastPathComponent) 会话已创建")
                requestRefresh()
            } catch {
                Self.removeTemporaryImages(prompt.imageURLs)
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                showTransientStatus(message, duration: 15)
                NSSound.beep()
            }
            conversationInFlight = false
            desktopPanelController.setNewConversationBusy(false)
        }
    }

    private func submitCodexCardPrompt(itemID: String, prompt: CodexPrompt) {
        let threadID = String(itemID.dropFirst("codex:".count))
        guard !ownershipTransfersInFlight.contains(threadID),
              CodexConversationBridge.ownershipState(threadID: threadID) != .transferring else {
            desktopPanelController.updateCodexCardStatus(
                itemID: itemID,
                text: "正在转移到 Codex，工作岛已停止发送指令",
                isBusy: true
            )
            return
        }
        guard !cardConversationsInFlight.contains(itemID) else {
            desktopPanelController.updateCodexCardStatus(
                itemID: itemID,
                text: "上一条指令仍在发送",
                isBusy: true
            )
            return
        }
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
            defer { Self.removeTemporaryImages(prompt.imageURLs) }
            do {
                let result = try await sendCodexCardPrompt(
                    prompt,
                    to: thread
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

    private func sendCodexCardPrompt(
        _ prompt: CodexPrompt,
        to thread: ActiveThread
    ) async throws -> CodexConversationResult {
        let route = CodexCardContinuationPolicy.route(
            threadID: thread.id,
            cwd: thread.cwd,
            isActive: thread.isActive
        )
        return try await CodexConversationBridge.send(prompt: prompt, route: route)
    }

    private static func removeTemporaryImages(_ urls: [URL]) {
        for url in urls where url.deletingLastPathComponent().lastPathComponent == "AIWorkIsland-PastedImages" {
            try? FileManager.default.removeItem(at: url)
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

    private func performRecordingHotKeyAction() {
        switch RecordingHotKeyIntent.resolve(isRecording: voiceMemoGuardianState != nil) {
        case .start:
            startVoiceMemoRecording()
        case .stopAndKeep:
            finishVoiceMemoRecording()
        }
    }

    @objc private func performRecordingHotKeyActionFromMenu() {
        performRecordingHotKeyAction()
    }

    private func updateRecordingHotKeyMenuItem(isRecording: Bool) {
        recordingHotKeyMenuItem?.title = isRecording
            ? "停止录音并保留（全局 Caps Lock + R）"
            : "开始语音备忘录（全局 Caps Lock + R）"
    }

    private func finishVoiceMemoRecording() {
        desktopPanelController.updateRecordingStopInProgress(true)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await voiceMemoLauncher.finishAndKeep()
                voiceMemoGuardian.recordingDidFinish()
                showTransientStatus("录音已结束并保留；将自动进入会议纪要流程")
            } catch {
                desktopPanelController.updateRecordingStopInProgress(false)
                if case VoiceMemoLauncher.LauncherError.accessibilityRequired = error {
                    _ = accessibilityController.requestAccessibilityAccess()
                }
                showSettingError(error)
            }
        }
    }

    @objc private func finishVoiceMemoFromMenu() {
        finishVoiceMemoRecording()
    }

    @objc private func continueVoiceMemoFromMenu() {
        voiceMemoGuardian.continueRecording()
        showTransientStatus("继续录音；15 分钟内不重复提醒")
    }

    private func configureRecordingNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let finish = UNNotificationAction(
            identifier: Self.finishRecordingAction,
            title: "结束并保留",
            options: [.foreground]
        )
        let keepGoing = UNNotificationAction(
            identifier: Self.continueRecordingAction,
            title: "继续录音",
            options: []
        )
        let recordingCategory = UNNotificationCategory(
            identifier: Self.recordingReminderCategory,
            actions: [finish, keepGoing],
            intentIdentifiers: [],
            options: []
        )
        let keepTodo = UNNotificationAction(
            identifier: Self.keepMeetingTodoAction,
            title: "保留到提醒事项",
            options: [.foreground]
        )
        let deleteTodo = UNNotificationAction(
            identifier: Self.deleteMeetingTodoAction,
            title: "删除",
            options: [.destructive]
        )
        let todoCategory = UNNotificationCategory(
            identifier: Self.meetingTodoCategory,
            actions: [keepTodo, deleteTodo],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([recordingCategory, todoCategory])
    }

    private func requestRecordingNotificationAuthorizationIfNeeded() {
        guard !didRequestRecordingNotificationAuthorization else { return }
        didRequestRecordingNotificationAuthorization = true
        RecordingNotificationAuthorization.request { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                self.recordingNotificationsAuthorized = granted
                self.processMeetingTodoConfirmations()
            }
        }
    }

    private func processMeetingTodoConfirmations() {
        guard !isSilentMode else { return }
        let candidates = meetingTodoQueue.pendingCandidates()
        for candidate in candidates where !notifiedMeetingTodoIDs.contains(candidate.id) {
            notifiedMeetingTodoIDs.insert(candidate.id)
            if recordingNotificationsAuthorized {
                showMeetingTodoNotification(candidate)
            } else if !meetingTodoAlertVisible {
                showMeetingTodoAlert(candidate)
                break
            }
        }
    }

    private func showMeetingTodoNotification(_ candidate: MeetingTodoCandidate) {
        let content = UNMutableNotificationContent()
        content.title = "会议待办确认"
        let metadata = [candidate.owner, candidate.dueDate]
            .filter { !$0.isEmpty && $0 != "待确认" }
            .joined(separator: " · ")
        content.body = metadata.isEmpty ? candidate.title : "\(candidate.title)\n\(metadata)"
        content.sound = .default
        content.categoryIdentifier = Self.meetingTodoCategory
        content.userInfo = ["meetingTodoID": candidate.id]
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "meeting-todo-\(candidate.id)",
            content: content,
            trigger: nil
        ))
    }

    private func showMeetingTodoAlert(_ candidate: MeetingTodoCandidate) {
        meetingTodoAlertVisible = true
        let alert = NSAlert()
        alert.messageText = "这是你要保留的待办吗？"
        alert.informativeText = "\(candidate.title)\n\n来源：\(candidate.meetingTitle)"
        alert.addButton(withTitle: "保留到提醒事项")
        alert.addButton(withTitle: "删除")
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        let keep = alert.runModal() == .alertFirstButtonReturn
        meetingTodoAlertVisible = false
        resolveMeetingTodo(candidate, keep: keep)
    }

    private func resolveMeetingTodo(_ candidate: MeetingTodoCandidate, keep: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if keep {
                    try await meetingReminderWriter.save(candidate)
                }
                try meetingTodoQueue.discard(candidate)
                showTransientStatus(keep ? "已保留到提醒事项" : "已删除会议待办")
            } catch {
                notifiedMeetingTodoIDs.remove(candidate.id)
                showTransientStatus("处理会议待办失败：\(error.localizedDescription)", duration: 15)
            }
            processMeetingTodoConfirmations()
        }
    }

    private func showRecordingSilenceReminder(_ state: VoiceMemoGuardianState) {
        guard !isSilentMode else { return }
        guard recordingNotificationsAuthorized else {
            showRecordingSilenceAlert()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "语音备忘录可能仍在录音"
        content.body = "已连续静音 5 分钟。请选择结束并保留，或继续录音。"
        content.sound = .default
        content.categoryIdentifier = Self.recordingReminderCategory
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "voice-memo-silence-\(Int(state.startedAt.timeIntervalSince1970))",
            content: content,
            trigger: nil
        ))
    }

    private func showRecordingSilenceAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "语音备忘录可能仍在录音"
        alert.informativeText = "已连续静音 5 分钟。录音不会自动停止。"
        alert.addButton(withTitle: "结束并保留")
        alert.addButton(withTitle: "继续录音")
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        if alert.runModal() == .alertFirstButtonReturn {
            finishVoiceMemoRecording()
        } else {
            voiceMemoGuardian.continueRecording()
        }
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
        processMeetingTodoConfirmations()
        // Keep quota refresh tied to the app's proven-active polling loop as
        // well as its dedicated timer. CompanyQuotaScanner enforces the
        // five-minute network interval, so this is cheap between due scans
        // and recovers if AppKit coalesces or drops the long-running timer.
        requestCompanyQuotaRefresh()
    }

    @objc private func companyQuotaTimerFired() {
        requestCompanyQuotaRefresh()
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

    @objc private func toggleSilentMode(_ sender: NSMenuItem) {
        isSilentMode.toggle()
        sender.state = isSilentMode ? .on : .off
        desktopPanelController.suppressesAutomaticReveals = isSilentMode
        if isSilentMode {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: pendingRecordingNotificationIdentifiers()
            )
            showTransientStatus("已开启静默运行")
        } else {
            showTransientStatus("已关闭静默运行")
        }
    }

    @objc private func selectAppearanceMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AppAppearanceMode(rawValue: raw) else { return }
        appearanceMode = mode
        for (candidate, item) in appearanceMenuItems {
            item.state = candidate == mode ? .on : .off
        }
        desktopPanelController.setAppearanceMode(mode)
        showTransientStatus("外观：\(mode.title)")
    }

    private func pendingRecordingNotificationIdentifiers() -> [String] {
        guard let state = voiceMemoGuardianState else { return [] }
        return ["voice-memo-silence-\(Int(state.startedAt.timeIntervalSince1970))"]
    }

    @objc private func toggleDesktopPanel(_ sender: NSMenuItem) {
        isDesktopPanelVisible.toggle()
        sender.state = isDesktopPanelVisible ? .on : .off
        if isDesktopPanelVisible {
            desktopPanelController.showAutoCollapsing()
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
    }

    @objc private func selectCleanContentMode() {
        setDesktopContentMode(.clean)
    }

    @objc private func selectDetailedContentMode() {
        setDesktopContentMode(.detailed)
    }

    private func setDesktopContentMode(_ mode: DesktopContentMode) {
        desktopContentMode = mode
        cleanContentModeMenuItem?.state = mode == .clean ? .on : .off
        detailedContentModeMenuItem?.state = mode == .detailed ? .on : .off
        desktopPanelController.setContentMode(mode)
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
        do {
            try IndependentAppRelauncher.schedule(bundlePath: bundlePath)
            NSApp.terminate(nil)
        } catch {
            showTransientStatus("重启失败：\(error.localizedDescription)", duration: 15)
            NSSound.beep()
        }
    }

    @objc private func checkForUpdates() {
        updateController.checkManually()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let meetingTodoID = response.notification.request.content.userInfo["meetingTodoID"] as? String
        completionHandler()
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch action {
            case Self.finishRecordingAction:
                finishVoiceMemoRecording()
            case Self.continueRecordingAction:
                voiceMemoGuardian.continueRecording()
                showTransientStatus("继续录音；15 分钟内不重复提醒")
            case Self.keepMeetingTodoAction, Self.deleteMeetingTodoAction,
                 UNNotificationDefaultActionIdentifier:
                guard let id = meetingTodoID,
                      let candidate = meetingTodoQueue.candidate(id: id) else { break }
                if action == UNNotificationDefaultActionIdentifier {
                    showMeetingTodoAlert(candidate)
                } else {
                    resolveMeetingTodo(candidate, keep: action == Self.keepMeetingTodoAction)
                }
            default:
                break
            }
        }
    }
}

private enum RecordingNotificationAuthorization {
    nonisolated static func request(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, _ in
            completion(granted)
        }
    }
}
