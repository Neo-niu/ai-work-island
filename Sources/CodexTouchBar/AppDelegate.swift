import AppKit
import CodexTouchBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let codexBundleIdentifier = "com.openai.codex"
    private static let hermesBundleIdentifier = "com.nousresearch.hermes.setup"
    private static let enabledDefaultsKey = "touchBarEnabled"
    private static let alwaysShowDefaultsKey = "touchBarAlwaysShow"

    private let scanner = RolloutScanner()
    private let hermesScanner = HermesStatusScanner()
    private let companyQuotaScanner = CompanyQuotaScanner()
    private let grouper = ProjectGrouper()
    private let touchBarController = TouchBarController()
    private let accessibilityController = CodexAccessibilityController()
    private var cycler = ThreadCycler()
    private var statusItem: NSStatusItem?
    private var statusMenuItem: NSMenuItem?
    private var enabledMenuItem: NSMenuItem?
    private var alwaysShowMenuItem: NSMenuItem?
    private var refreshTimer: Timer?
    private var refreshInFlight = false
    private var latestGroups: [ProjectGroup]?
    private var latestWeeklyLimit: WeeklyLimitUsage?
    private var latestHermesStatus = HermesStatus(
        gatewayRunning: false,
        connectedPlatforms: 0,
        runningTasks: 0,
        blockedTasks: 0,
        failedTasks: 0
    )
    private var latestCompanyQuota: CompanyModelQuota?
    private var latestGroupCount = 0
    private var latestThreadCount = 0
    private var latestUnreadThreadCount = 0
    private var transientStatus: (message: String, expiresAt: Date)?

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        let runningPIDs = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        ).map(\.processIdentifier)
        if SingleInstancePolicy.shouldTerminate(
            currentPID: ProcessInfo.processInfo.processIdentifier,
            runningPIDs: runningPIDs
        ) {
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        LaunchAtLoginController.registerIfNeeded()

        touchBarController.onProjectSelected = { [weak self] group in
            self?.openNextThread(in: group)
        }
        touchBarController.onEffortSelected = { [weak self] choice in
            self?.applyEffort(choice)
        }
        touchBarController.onSpeedSelected = { [weak self] choice in
            self?.applySpeed(choice)
        }
        touchBarController.onHermesSelected = { [weak self] in
            self?.openHermes()
        }
        touchBarController.onCompanyQuotaSelected = { [weak self] in
            self?.openCompanyQuotaPage()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        updateRefreshSchedule()
        requestRefresh()
        updatePresentation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        touchBarController.dismiss()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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

        let refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        let openCodexItem = NSMenuItem(title: "打开 Codex", action: #selector(openCodex), keyEquivalent: "o")
        openCodexItem.target = self
        menu.addItem(openCodexItem)

        let openHermesItem = NSMenuItem(title: "打开 Hermes", action: #selector(openHermes), keyEquivalent: "h")
        openHermesItem.target = self
        menu.addItem(openHermesItem)

        let accessibilityItem = NSMenuItem(
            title: "启用推理程度控制…",
            action: #selector(requestAccessibilityAccess),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 Codex Hermes Touch Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        self.statusItem = statusItem
        self.statusMenuItem = statusMenuItem
        self.enabledMenuItem = enabledMenuItem
        self.alwaysShowMenuItem = alwaysShowMenuItem

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

        Task { [weak self, scanner, hermesScanner, companyQuotaScanner, grouper] in
            let snapshot = await scanner.scanSnapshot()
            let hermesStatus = hermesScanner.scan()
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
                weeklyLimit: snapshot.weeklyLimit,
                hermesStatus: hermesStatus,
                companyQuota: companyQuota
            )
            self.refreshInFlight = false
        }
    }

    private func apply(
        groups: [ProjectGroup],
        weeklyLimit: WeeklyLimitUsage?,
        hermesStatus: HermesStatus,
        companyQuota: CompanyModelQuota?
    ) {
        if RefreshPolicy.shouldApply(previous: latestGroups, next: groups) {
            latestGroups = groups
            latestGroupCount = groups.count
            latestThreadCount = groups.reduce(0) {
                $0 + $1.threads.filter(\.isActive).count
            }
            latestUnreadThreadCount = groups.reduce(0) {
                $0 + $1.threads.filter(\.isUnread).count
            }
            cycler.retainGroups(Set(groups.map(\.id)))
            touchBarController.update(groups: groups)
        }

        if latestWeeklyLimit != weeklyLimit {
            latestWeeklyLimit = weeklyLimit
            touchBarController.showWeeklyLimit(weeklyLimit)
        }
        if latestHermesStatus != hermesStatus {
            latestHermesStatus = hermesStatus
            touchBarController.showHermesStatus(hermesStatus)
        }
        if latestCompanyQuota != companyQuota {
            latestCompanyQuota = companyQuota
            touchBarController.showCompanyQuota(companyQuota)
        }
        updateStatusText()
    }

    private func updateStatusText() {
        guard touchBarController.isAvailable else {
            statusMenuItem?.title = "当前系统不支持 Touch Bar 常驻接口"
            return
        }

        if let transientStatus, transientStatus.expiresAt > Date() {
            statusMenuItem?.title = transientStatus.message
            return
        }
        transientStatus = nil

        if latestThreadCount == 0, latestUnreadThreadCount == 0 {
            statusMenuItem?.title = "Codex 空闲 · \(latestHermesStatus.compactTitle)"
        } else {
            let unreadStatus = latestUnreadThreadCount > 0
                ? " · \(latestUnreadThreadCount) 个待读"
                : ""
            statusMenuItem?.title = "\(latestThreadCount) 个运行任务\(unreadStatus) · \(latestGroupCount) 个项目"
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

    private var isSupportedAppFrontmost: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return bundleID == Self.codexBundleIdentifier || bundleID == Self.hermesBundleIdentifier
    }

    private var shouldPresentDashboard: Bool {
        isEnabled && (alwaysShow || isSupportedAppFrontmost)
    }

    private func updateRefreshSchedule() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        guard let interval = RefreshPolicy.pollInterval(isDashboardVisible: shouldPresentDashboard) else {
            return
        }
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

    private func openNextThread(in group: ProjectGroup) {
        guard let thread = cycler.nextThread(in: group),
              let url = URL(string: "codex://threads/\(thread.id)") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func applyEffort(_ choice: EffortChoice) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accessibilityController.apply(effort: choice)
                touchBarController.showSelectedEffort(choice)
                showTransientStatus("推理程度已设为\(choice.shortTitle)")
            } catch {
                showSettingError(error)
            }
        }
    }

    private func applySpeed(_ choice: SpeedChoice) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await accessibilityController.apply(speed: choice)
                touchBarController.showSelectedSpeed(choice)
                showTransientStatus("响应速度已设为\(choice.title)")
            } catch {
                showSettingError(error)
            }
        }
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

    @objc private func openCompanyQuotaPage() {
        NSWorkspace.shared.open(URL(string: "https://model.zhenguanyu.com/console/usage/dashboard")!)
    }

    @objc private func requestAccessibilityAccess() {
        if accessibilityController.requestAccessibilityAccess() {
            showTransientStatus("辅助功能权限已启用")
        } else {
            showTransientStatus(
                "请在系统设置 → 隐私与安全性 → 辅助功能中启用本应用",
                duration: 15
            )
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
