@preconcurrency import AppKit
import CodexTouchBarCore
import PrivateTouchBar

@MainActor
final class TouchBarController: NSObject {
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.kanyun.CodexHermesTouchBar.dashboard")
    private static let projectStatusItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.project-status")
    private static let tokenUsageItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.token-usage")
    private static let companyQuotaItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.company-quota")
    private static let trayItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.tray")

    var onProcessingSelected: (() -> Void)?
    var onUnreadSelected: (() -> Void)?

    private(set) var isAvailable = false
    private(set) var isPresented = false
    private let touchBar = NSTouchBar()
    private let trayItem: NSCustomTouchBarItem
    private var trayItemWasAdded = false

    private lazy var projectStatusView = TaskStatusView()
    private lazy var tokenUsageView = QuotaRingView()
    private lazy var companyQuotaView = QuotaRingView()
    override init() {
        let item = NSCustomTouchBarItem(identifier: Self.trayItemIdentifier)
        let button = NSButton(
            image: NSImage(systemSymbolName: "chart.xyaxis.line", accessibilityDescription: "Codex 状态仪表盘") ?? NSImage(),
            target: nil,
            action: nil
        )
        button.bezelStyle = .texturedRounded
        item.view = button
        trayItem = item

        super.init()
        button.target = self
        button.action = #selector(showFromTray)
        projectStatusView.onProcessingSelected = { [weak self] in
            self?.onProcessingSelected?()
        }
        projectStatusView.onUnreadSelected = { [weak self] in
            self?.onUnreadSelected?()
        }
        configureTouchBar()
    }

    deinit {
        MainActor.assumeIsolated {
            if isPresented {
                CTBDismissSystemModalTouchBar(touchBar)
                CTBSetCloseBoxVisible(true)
            }
            if trayItemWasAdded {
                CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
                CTBRemoveSystemTrayItem(trayItem)
            }
        }
    }

    func update(groups: [ProjectGroup]) {
        let threads = groups.flatMap(\.threads)
        let processing = threads.filter(\.isActive).count
        let unread = threads.filter(\.isUnread).count
        projectStatusView.update(processing: processing, unread: unread)
    }

    func showCodexLimits(shortTerm: WeeklyLimitUsage?, weekly: WeeklyLimitUsage?) {
        let available = [shortTerm, weekly].compactMap { $0 }
        guard !available.isEmpty else {
            tokenUsageView.update(title: "Codex", remainingPercent: nil)
            return
        }
        let detail = [
            shortTerm.map { "5时 \($0.remainingPercent)%" },
            weekly.map { "周 \($0.remainingPercent)%" },
        ].compactMap { $0 }.joined(separator: " · ")
        let accessibility = [
            shortTerm.map { "5小时额度剩余 \($0.remainingPercent)%" },
            weekly.map { "周额度剩余 \($0.remainingPercent)%" },
        ].compactMap { $0 }.joined(separator: "，")
        tokenUsageView.update(
            title: "Codex",
            remainingPercent: available.map(\.remainingPercent).min(),
            detail: detail,
            accessibilityText: accessibility
        )
    }

    func showWeeklyLimit(_ usage: WeeklyLimitUsage?) {
        showCodexLimits(shortTerm: nil, weekly: usage)
    }

    func showCompanyQuota(_ quota: CompanyModelQuota?) {
        guard let quota else {
            companyQuotaView.update(
                title: "公司",
                remainingPercent: nil,
                detail: "待配置",
                accessibilityText: "公司额度待配置，请在 Edge 登录公司模型平台"
            )
            return
        }
        companyQuotaView.update(
            title: "公司",
            remainingPercent: quota.remainingPercent,
            detail: String(format: "$%.2f 剩余", quota.remainingUSD),
            accessibilityText: String(
                format: "公司额度剩余 $%.2f，%d%%",
                quota.remainingUSD,
                quota.remainingPercent
            )
        )
    }

    @discardableResult
    func present() -> Bool {
        if isPresented { return true }
        guard isAvailable else { return false }
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, true)
        }
        CTBSetCloseBoxVisible(true)
        isPresented = CTBPresentSystemModalTouchBar(touchBar, Self.trayItemIdentifier.rawValue)
        return isPresented
    }

    @discardableResult
    func restorePresentation() -> Bool {
        if isPresented {
            CTBDismissSystemModalTouchBar(touchBar)
            isPresented = false
        }
        return present()
    }

    func dismiss() {
        guard isPresented else { return }
        CTBDismissSystemModalTouchBar(touchBar)
        CTBSetCloseBoxVisible(true)
        isPresented = false
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    private func configureTouchBar() {
        isAvailable = CTBPrivateTouchBarIsAvailable()
        guard isAvailable else { return }
        touchBar.customizationIdentifier = Self.barIdentifier
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            Self.projectStatusItemIdentifier,
            Self.companyQuotaItemIdentifier,
            Self.tokenUsageItemIdentifier,
        ]
        trayItemWasAdded = CTBAddSystemTrayItem(trayItem)
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    @objc private func showFromTray() {
        _ = present()
    }
}

@MainActor
extension TouchBarController: NSTouchBarDelegate {
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        let item = NSCustomTouchBarItem(identifier: identifier)
        switch identifier {
        case Self.projectStatusItemIdentifier:
            item.customizationLabel = "Codex 运行状态"
            item.view = projectStatusView
        case Self.tokenUsageItemIdentifier:
            item.customizationLabel = "Codex 剩余额度"
            item.view = tokenUsageView
        case Self.companyQuotaItemIdentifier:
            item.customizationLabel = "公司额度"
            item.view = companyQuotaView
        default:
            return nil
        }
        return item
    }
}
