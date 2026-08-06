@preconcurrency import AppKit
import CodexTouchBarCore
import PrivateTouchBar

@MainActor
final class TouchBarController: NSObject {
    private static let barIdentifier = NSTouchBar.CustomizationIdentifier("dev.kanyun.CodexHermesTouchBar.dashboard")
    private static let projectStatusItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.project-status")
    private static let tokenUsageItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.token-usage")
    private static let companyQuotaItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.company-quota")
    private static let hermesItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.hermes")
    private static let effortItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.effort-slider")
    private static let petItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.pet")
    private static let trayItemIdentifier = NSTouchBarItem.Identifier("dev.kanyun.CodexHermesTouchBar.tray")

    var onProjectSelected: ((ProjectGroup) -> Void)?
    var onEffortSelected: ((EffortChoice) -> Void)?
    var onSpeedSelected: ((SpeedChoice) -> Void)?
    var onHermesSelected: (() -> Void)?
    var onCompanyQuotaSelected: (() -> Void)?

    private(set) var isAvailable = false
    private(set) var isPresented = false
    private let touchBar = NSTouchBar()
    private let trayItem: NSCustomTouchBarItem
    private var trayItemWasAdded = false
    private var selectedEffort: EffortChoice = .medium
    private var effortApplyWorkItem: DispatchWorkItem?

    private lazy var projectStatusView = makeReadOnlyStatusView(
        title: "Codex 空闲",
        symbolName: "circle.dotted"
    )
    private lazy var tokenUsageView = QuotaProgressView()
    private lazy var companyQuotaView = QuotaProgressView()
    private lazy var hermesStatusView = makeReadOnlyStatusView(
        title: "Hermes 离线",
        symbolName: "sparkles"
    )
    private lazy var effortSlider: NSSlider = {
        let slider = NSSlider(
            value: Double(EffortChoice.allCases.firstIndex(of: selectedEffort) ?? 1),
            minValue: 0,
            maxValue: Double(EffortChoice.allCases.count - 1),
            target: self,
            action: #selector(effortSliderChanged(_:))
        )
        slider.numberOfTickMarks = EffortChoice.allCases.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .small
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
        slider.setAccessibilityLabel("推理程度")
        return slider
    }()
    private lazy var effortFeedbackView = EffortFeedbackView()
    private lazy var effortLabel: NSTextField = {
        let label = NSTextField(labelWithString: effortDisplayTitle)
        label.textColor = .white
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()
    private lazy var petView = SiriPetView()

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
        configureTouchBar()
    }

    deinit {
        MainActor.assumeIsolated {
            effortApplyWorkItem?.cancel()
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
        let title = "处理中 \(processing) · 待查看 \(unread)"
        update(
            projectStatusView,
            title: title,
            symbolName: unread > 0 ? "bell.badge.fill" : (processing > 0 ? "waveform.circle.fill" : "circle.dotted"),
            color: unread > 0 ? .systemPurple : .white
        )
        petView.setActive(processing > 0)
    }

    func showSelectedEffort(_ choice: EffortChoice) {
        selectedEffort = choice
        effortSlider.doubleValue = Double(EffortChoice.allCases.firstIndex(of: choice) ?? 1)
        effortLabel.stringValue = effortDisplayTitle
        effortSlider.setAccessibilityValue(choice.title)
        effortFeedbackView.select(
            index: EffortChoice.allCases.firstIndex(of: choice) ?? 1,
            animated: true
        )
    }

    func showWeeklyLimit(_ usage: WeeklyLimitUsage?) {
        guard let usage else {
            tokenUsageView.update(title: "周额度 —", usedPercent: nil)
            return
        }
        let used = Int(usage.usedPercent.rounded())
        let low = usage.remainingPercent <= 20
        tokenUsageView.update(
            title: "周 \(used)%",
            usedPercent: used,
            isLow: low
        )
    }

    func showSelectedSpeed(_ choice: SpeedChoice) {}

    func showHermesStatus(_ status: HermesStatus) {
        update(
            hermesStatusView,
            title: status.compactTitle,
            symbolName: status.needsAttention ? "exclamationmark.circle.fill" : "sparkles",
            color: status.needsAttention ? .systemRed : .white
        )
    }

    func showCompanyQuota(_ quota: CompanyModelQuota?) {
        guard let quota else {
            companyQuotaView.update(title: "公司 —", usedPercent: nil)
            return
        }
        let used = max(0, min(100, 100 - quota.remainingPercent))
        let low = quota.remainingPercent <= 20
        companyQuotaView.update(title: "公司 \(used)%", usedPercent: used, isLow: low)
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

    func dismiss() {
        guard isPresented else { return }
        CTBDismissSystemModalTouchBar(touchBar)
        CTBSetCloseBoxVisible(true)
        isPresented = false
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    private var effortDisplayTitle: String {
        "推理 \(selectedEffort.shortTitle)"
    }

    private func configureTouchBar() {
        isAvailable = CTBPrivateTouchBarIsAvailable()
        guard isAvailable else { return }
        touchBar.customizationIdentifier = Self.barIdentifier
        touchBar.delegate = self
        touchBar.defaultItemIdentifiers = [
            Self.petItemIdentifier,
            Self.projectStatusItemIdentifier,
            .flexibleSpace,
            Self.tokenUsageItemIdentifier,
            Self.companyQuotaItemIdentifier,
            Self.hermesItemIdentifier,
            Self.effortItemIdentifier,
        ]
        trayItemWasAdded = CTBAddSystemTrayItem(trayItem)
        if trayItemWasAdded {
            CTBSetControlStripPresence(Self.trayItemIdentifier.rawValue, false)
        }
    }

    private func makeReadOnlyStatusView(title: String, symbolName: String) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyDown
        view.imageAlignment = .alignCenter
        view.image = TouchBarImageRenderer.image(title: title, symbolName: symbolName)
        view.setAccessibilityLabel(title)
        return view
    }

    private func update(_ view: NSImageView, title: String, symbolName: String, color: NSColor = .white) {
        view.image = TouchBarImageRenderer.image(
            title: title,
            symbolName: symbolName,
            font: .systemFont(ofSize: 12, weight: .medium),
            textColor: color
        )
        view.setAccessibilityLabel(title)
    }

    private func makeEffortView() -> NSView {
        let stack = NSStackView(views: [effortLabel, effortSlider, effortFeedbackView])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = -3
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        return stack
    }

    @objc private func effortSliderChanged(_ sender: NSSlider) {
        let index = max(0, min(EffortChoice.allCases.count - 1, Int(sender.doubleValue.rounded())))
        let choice = EffortChoice.allCases[index]
        showSelectedEffort(choice)
        effortApplyWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onEffortSelected?(choice)
        }
        effortApplyWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
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
            item.customizationLabel = "Token 使用"
            item.view = tokenUsageView
        case Self.companyQuotaItemIdentifier:
            item.customizationLabel = "公司额度"
            item.view = companyQuotaView
        case Self.hermesItemIdentifier:
            item.customizationLabel = "Hermes 状态"
            item.view = hermesStatusView
        case Self.effortItemIdentifier:
            item.customizationLabel = "推理程度"
            item.view = makeEffortView()
        case Self.petItemIdentifier:
            item.customizationLabel = "Touch Bar 宠物"
            item.view = petView
        default:
            return nil
        }
        return item
    }
}
