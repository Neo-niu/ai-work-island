import AppKit
import CodexTouchBarCore
import QuartzCore

enum DesktopPanelMode: Equatable {
    case background
    case floating
}

enum DesktopPanelWindowPolicy {
    static func floatsAboveFullScreen(
        mode: DesktopPanelMode,
        hoverExpanded: Bool
    ) -> Bool {
        mode == .floating || hoverExpanded
    }
}

enum DesktopPanelLayout {
    static let width: CGFloat = 372

    static func contentSize(
        visibleItemCount: Int,
        sectionCount: Int = 0,
        conversationItemCount: Int = 0
    ) -> NSSize {
        let baseHeight = 144
        let itemHeight = max(1, visibleItemCount) * 62
        let sectionHeight = sectionCount * 22
        let conversationHeight = conversationItemCount * 40
        let height = CGFloat(baseHeight + itemHeight + sectionHeight + conversationHeight)
        return NSSize(width: width, height: min(height, 700))
    }
}

enum DesktopFloatingButtonLayout {
    static let size = NSSize(width: 108, height: 38)
    static let animationInset: CGFloat = 6
    static let canvasSize = NSSize(
        width: size.width + animationInset * 2,
        height: size.height + animationInset * 2
    )
    static let cornerRadius: CGFloat = size.height / 2
    static let statusDotSize: CGFloat = 8
}

struct DesktopFloatingButtonPresentation: Equatable {
    let displayText: String
    let tintColor: NSColor
    let pulses: Bool
    let accessibilityLabel: String

    static func make(items: [WorkItem], latestCompleted: WorkItem?) -> Self {
        let waitingCount = items.filter { $0.status == .waiting }.count
        let issueCount = items.filter { $0.status == .failed || $0.status == .stale }.count
        let activeCount = items.filter { $0.status.isActiveWork }.count

        let displayText: String
        let tintColor: NSColor
        let pulses: Bool
        if issueCount > 0 {
            displayText = "\(issueCount) 需处理"
            tintColor = .systemRed
            pulses = false
        } else if waitingCount > 0 {
            displayText = "\(waitingCount) 等待你"
            tintColor = .systemOrange
            pulses = false
        } else if activeCount > 0 {
            displayText = "\(activeCount) 运行"
            tintColor = .systemBlue
            pulses = true
        } else if latestCompleted != nil {
            displayText = "已完成"
            tintColor = .systemGreen
            pulses = false
        } else {
            displayText = "空闲"
            tintColor = .secondaryLabelColor
            pulses = false
        }

        let accessibilityLabel = "恢复 AI 工作岛；当前\(displayText)"
        return Self(
            displayText: displayText,
            tintColor: tintColor,
            pulses: pulses,
            accessibilityLabel: accessibilityLabel
        )
    }
}

enum DesktopFloatingButtonMotion {
    static let entranceDuration: TimeInterval = 0.42
    static let transitionDuration: TimeInterval = 0.62
    static let ambientCycleDuration: TimeInterval = 2.4
    static let borderCycleDuration: TimeInterval = 1.8

    static func shouldAnimateTransition(
        from previous: DesktopFloatingButtonPresentation?,
        to current: DesktopFloatingButtonPresentation,
        reduceMotion: Bool
    ) -> Bool {
        guard !reduceMotion, let previous else { return false }
        return previous != current
    }
}

enum DesktopFloatingPanelTransition {
    static func shouldFinishMinimizing(isMinimizedToFloatingButton: Bool) -> Bool {
        isMinimizedToFloatingButton
    }
}

enum DesktopFloatingHoverBehavior {
    static let collapseDelay: TimeInterval = 0.5

    static func shouldAutoCollapse(
        isHoverExpanded: Bool,
        isPanelHovered: Bool,
        isInteractionActive: Bool = false
    ) -> Bool {
        isHoverExpanded && !isPanelHovered && !isInteractionActive
    }
}

struct DesktopFloatingButtonMotionSnapshot: Equatable {
    let root: Set<String>
    let statusDot: Set<String>
    let ripple: Set<String>
    let ambient: Set<String>
    let border: Set<String>
    let sheen: Set<String>
}

struct DesktopPanelItemPresentation: Equatable {
    let id: String
    let title: String
    let detail: String
    let status: WorkItemStatus
    let outputPath: String?
    let openURL: String?
    let phase: String?
    let phaseIndex: Int?
    let phaseCount: Int?
    let lastAssistantResult: String?

    init(_ item: WorkItem, lastAssistantResult: String? = nil) {
        id = item.id
        title = item.displayTitle
        detail = item.displayDetail
        status = item.status
        outputPath = item.outputPath
        openURL = item.openURL
        phase = item.phase
        phaseIndex = item.phaseIndex
        phaseCount = item.phaseCount
        self.lastAssistantResult = lastAssistantResult
    }
}

struct DesktopPanelContentSignature: Equatable {
    let items: [DesktopPanelItemPresentation]
    let automationIssues: [String]
    let layoutTokens: [String]

    init(
        snapshot: WorkStatusSnapshot,
        layoutTokens: [String],
        codexResults: [String: String]
    ) {
        items = snapshot.items.map {
            DesktopPanelItemPresentation($0, lastAssistantResult: codexResults[$0.id])
        }
        automationIssues = snapshot.automationIssues
        self.layoutTokens = layoutTokens
    }
}

enum WorkSection: String, CaseIterable, Hashable {
    case needsUser
    case active
    case queued
    case recent

    var title: String {
        switch self {
        case .active: "正在执行"
        case .queued: "等待系统"
        case .needsUser: "等待你"
        case .recent: "最近完成"
        }
    }

    var isAlwaysExpanded: Bool { self == .needsUser }
}

private struct WorkSectionLayout {
    let section: WorkSection
    let totalCount: Int
    let items: [WorkItem]
    let isExpanded: Bool
}

private struct WorkPanelLayout {
    let sections: [WorkSectionLayout]
    var rowCount: Int { sections.reduce(0) { $0 + $1.items.count } }
    var tokens: [String] {
        sections.flatMap { layout in
            ["section:\(layout.section.rawValue):\(layout.isExpanded)"] + layout.items.map(\.id)
        }
    }
}

@MainActor
final class DesktopStatusPanelController: NSObject, NSWindowDelegate {
    var onItemSelected: ((WorkItem) -> Void)?
    var onItemDetailsSelected: ((WorkItem) -> Void)?
    var onItemOutputSelected: ((WorkItem) -> Void)?
    var onCodexPromptSubmitted: ((String, String) -> Void)?
    var onNewConversationSelected: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    private let panel: NSPanel
    private let floatingPanel: NSPanel
    private let floatingButtonView = FloatingStatusButtonView()
    private let titleLabel = NSTextField(labelWithString: "AI 工作岛")
    private let statusCapsule = StatusCapsuleView()
    private let newConversationButton = NSButton()
    private let codexQuotaView = DesktopQuotaSummaryView()
    private let companyQuotaView = DesktopQuotaSummaryView()
    private let quotaStack = NSStackView()
    private let itemStack = NSStackView()
    private let footerLabel = NSTextField(labelWithString: "")
    private var displayedItemIDs: [String]?
    private var displayedRowCount = 0
    private var isTransitioningItems = false
    private var pendingSnapshot: WorkStatusSnapshot?
    private var lastStatuses: [String: WorkItemStatus] = [:]
    private var pendingSweepColors: [String: NSColor] = [:]
    private var expandedSections: Set<WorkSection> = []
    private var didChooseDefaultSection = false
    private var latestSnapshot: WorkStatusSnapshot?
    private var displayedContentSignature: DesktopPanelContentSignature?
    private var isMinimizedToFloatingButton = false
    private var didPositionFloatingPanel = false
    private var isHoverExpanded = false
    private var isPanelHovered = false
    private var pendingAutoCollapse: DispatchWorkItem?
    private var isConversationEditing = false
    private var codexResults: [String: String] = [:]
    private var codexRows: [String: WorkItemRowView] = [:]
    private var displayMode: DesktopPanelMode = .background

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesktopPanelLayout.width, height: 180),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        floatingPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
        configureFloatingPanel()
    }

    var isVisible: Bool { panel.isVisible || floatingPanel.isVisible }

    func setDisplayMode(_ mode: DesktopPanelMode) {
        displayMode = mode
        applyDisplayMode(hoverExpanded: isHoverExpanded && !isMinimizedToFloatingButton)
    }

    private func applyDisplayMode(hoverExpanded: Bool) {
        let floatsAboveFullScreen = DesktopPanelWindowPolicy.floatsAboveFullScreen(
            mode: displayMode,
            hoverExpanded: hoverExpanded
        )
        switch displayMode {
        case .background:
            panel.styleMask.remove(.closable)
            panel.isFloatingPanel = floatsAboveFullScreen
            panel.level = floatsAboveFullScreen
                ? .floating
                : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2)
            panel.collectionBehavior = floatsAboveFullScreen
                ? [.canJoinAllSpaces, .fullScreenAuxiliary]
                : [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.standardWindowButton(.closeButton)?.isHidden = true
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
        case .floating:
            panel.styleMask.insert(.closable)
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.standardWindowButton(.closeButton)?.isHidden = false
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }

    func show() {
        cancelPendingAutoCollapse()
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        applyDisplayMode(hoverExpanded: false)
        floatingPanel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    func showCollapsed() {
        cancelPendingAutoCollapse()
        isHoverExpanded = false
        isMinimizedToFloatingButton = true
        applyDisplayMode(hoverExpanded: false)
        positionFloatingPanelIfNeeded()
        panel.orderOut(nil)
        floatingPanel.alphaValue = 1
        floatingPanel.orderFrontRegardless()
    }

    func hide() {
        cancelPendingAutoCollapse()
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        applyDisplayMode(hoverExpanded: false)
        panel.orderOut(nil)
        floatingPanel.orderOut(nil)
    }

    func update(snapshot: WorkStatusSnapshot) {
        latestSnapshot = snapshot
        floatingButtonView.update(snapshot: snapshot)
        captureStatusEffects(in: snapshot)
        updateQuotaViews(snapshot: snapshot)
        if isTransitioningItems {
            pendingSnapshot = snapshot
            return
        }
        let layout = panelLayout(for: snapshot)
        let visibleIDs = layout.tokens
        let contentSignature = DesktopPanelContentSignature(
            snapshot: snapshot,
            layoutTokens: visibleIDs,
            codexResults: codexResults
        )
        guard displayedContentSignature != contentSignature else {
            return
        }
        guard let displayedItemIDs else {
            self.displayedItemIDs = visibleIDs
            displayedRowCount = layout.rowCount
            displayedContentSignature = contentSignature
            apply(snapshot: snapshot, resizeImmediately: true)
            return
        }
        guard displayedItemIDs != visibleIDs,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            self.displayedItemIDs = visibleIDs
            displayedRowCount = layout.rowCount
            displayedContentSignature = contentSignature
            apply(snapshot: snapshot, resizeImmediately: true)
            return
        }
        animateTransition(
            to: snapshot,
            visibleIDs: visibleIDs,
            contentSignature: contentSignature,
            newRowCount: layout.rowCount
        )
    }

    func setNewConversationBusy(_ isBusy: Bool) {
        newConversationButton.isEnabled = !isBusy
        newConversationButton.toolTip = isBusy ? "正在创建新会话" : "新建 Codex 会话"
    }

    func updateCodexCardResults(from groups: [ProjectGroup]) {
        codexResults = Dictionary(uniqueKeysWithValues: groups.flatMap { group in
            group.threads.compactMap { thread in
                thread.lastAssistantResult.map { ("codex:\(thread.id)", $0) }
            }
        })
    }

    func updateCodexCardStatus(
        itemID: String,
        text: String,
        isBusy: Bool = false
    ) {
        codexRows[itemID]?.updateConversationStatus(text, isBusy: isBusy)
    }

    private func apply(snapshot: WorkStatusSnapshot, resizeImmediately: Bool) {
        let running = snapshot.items.filter { $0.status == .running }.count
        let queued = snapshot.items.filter { $0.status == .queued }.count
        let attention = snapshot.items.filter {
            $0.status == .waiting || $0.status == .failed || $0.status == .stale
        }.count
        if snapshot.items.isEmpty {
            statusCapsule.update(text: "全部空闲", color: .secondaryLabelColor)
        } else if attention > 0 {
            statusCapsule.update(text: "\(running) 运行 · \(attention) 待处理", color: .systemOrange)
        } else if queued > 0 {
            statusCapsule.update(text: "\(running) 运行 · \(queued) 等待", color: .systemIndigo)
        } else {
            statusCapsule.update(text: "\(running) 运行", color: .systemBlue)
        }

        itemStack.arrangedSubviews.forEach {
            itemStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        codexRows.removeAll(keepingCapacity: true)

        let layout = panelLayout(for: snapshot)
        if snapshot.items.isEmpty {
            let empty = NSTextField(labelWithString: "Codex 和自动化程序当前没有活动任务")
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            empty.font = .systemFont(ofSize: 13)
            empty.heightAnchor.constraint(equalToConstant: 52).isActive = true
            itemStack.addArrangedSubview(empty)
        } else {
            for sectionLayout in layout.sections {
                let header = WorkSectionHeaderView(
                    title: sectionLayout.section.title,
                    count: sectionLayout.totalCount,
                    expanded: sectionLayout.isExpanded,
                    collapsible: !sectionLayout.section.isAlwaysExpanded
                )
                if !sectionLayout.section.isAlwaysExpanded {
                    header.onToggle = { [weak self] in
                        self?.toggle(section: sectionLayout.section)
                    }
                }
                itemStack.addArrangedSubview(header)
                for item in sectionLayout.items {
                    let row = WorkItemRowView(
                        item: item,
                        lastAssistantResult: codexResults[item.id]
                    )
                    row.onSelected = { [weak self] in self?.onItemSelected?(item) }
                    row.onDetailsSelected = { [weak self] in self?.onItemDetailsSelected?(item) }
                    row.onOutputSelected = item.outputPath == nil ? nil : { [weak self] in
                        self?.onItemOutputSelected?(item)
                    }
                    if item.id.hasPrefix("codex:") {
                        row.onPromptSubmitted = { [weak self] prompt in
                            self?.onCodexPromptSubmitted?(item.id, prompt)
                        }
                        row.onEditingChanged = { [weak self] editing in
                            self?.isConversationEditing = editing
                            if editing { self?.cancelPendingAutoCollapse() }
                        }
                        codexRows[item.id] = row
                    }
                    itemStack.addArrangedSubview(row)
                    if let color = pendingSweepColors.removeValue(forKey: item.id) {
                        DispatchQueue.main.async { row.playSuccessSweep(color: color) }
                    }
                }
            }
        }

        footerLabel.isHidden = snapshot.automationIssues.isEmpty
        footerLabel.stringValue = "状态文件异常 \(snapshot.automationIssues.count)"
        footerLabel.textColor = .systemRed

        if resizeImmediately {
            panel.setContentSize(DesktopPanelLayout.contentSize(
                visibleItemCount: layout.rowCount,
                sectionCount: layout.sections.count,
                conversationItemCount: layout.sections
                    .flatMap(\.items)
                    .filter { $0.id.hasPrefix("codex:") }
                    .count
            ))
        }
    }

    private func animateTransition(
        to snapshot: WorkStatusSnapshot,
        visibleIDs: [String],
        contentSignature: DesktopPanelContentSignature,
        newRowCount: Int
    ) {
        isTransitioningItems = true
        let oldCount = displayedRowCount
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            itemStack.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            displayedItemIDs = visibleIDs
            displayedRowCount = newRowCount
            displayedContentSignature = contentSignature
            apply(snapshot: snapshot, resizeImmediately: false)
            panel.contentView?.layoutSubtreeIfNeeded()

            let nextLayout = panelLayout(for: snapshot)
            let sectionCount = nextLayout.sections.count
            let contentSize = DesktopPanelLayout.contentSize(
                visibleItemCount: newRowCount,
                sectionCount: sectionCount,
                conversationItemCount: nextLayout.sections
                    .flatMap(\.items)
                    .filter { $0.id.hasPrefix("codex:") }
                    .count
            )
            let outerSize = panel.frameRect(
                forContentRect: NSRect(origin: .zero, size: contentSize)
            ).size
            var targetFrame = panel.frame
            targetFrame.origin.y = panel.frame.maxY - outerSize.height
            targetFrame.size = outerSize

            itemStack.alphaValue = 0
            itemStack.wantsLayer = true
            let offset: CGFloat = newRowCount >= oldCount ? -10 : 10
            let spring = CASpringAnimation(keyPath: "transform.translation.y")
            spring.fromValue = offset
            spring.toValue = 0
            spring.mass = 1
            spring.stiffness = 310
            spring.damping = 28
            spring.initialVelocity = 0
            spring.duration = min(0.42, spring.settlingDuration)
            itemStack.layer?.add(spring, forKey: "listArrival")

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.34
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(targetFrame, display: true)
                itemStack.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                guard let self else { return }
                isTransitioningItems = false
                if let pendingSnapshot {
                    self.pendingSnapshot = nil
                    update(snapshot: pendingSnapshot)
                }
            }
        }
    }

    private func updateQuotaViews(snapshot: WorkStatusSnapshot) {
        let codexLimits = [snapshot.codexShortTermLimit, snapshot.codexWeeklyLimit].compactMap { $0 }
        let codexText = [
            snapshot.codexShortTermLimit.map { "5时 \($0.remainingPercent)%" },
            snapshot.codexWeeklyLimit.map { "周 \($0.remainingPercent)%" },
        ].compactMap { $0 }.joined(separator: " · ")
        codexQuotaView.update(
            title: "Codex 额度",
            value: codexText,
            remainingPercent: codexLimits.map(\.remainingPercent).min()
        )
        codexQuotaView.isHidden = codexText.isEmpty

        if let quota = snapshot.companyQuota {
            companyQuotaView.update(
                title: "公司额度",
                value: String(format: "$%.2f · %d%%", quota.remainingUSD, quota.remainingPercent),
                remainingPercent: quota.remainingPercent
            )
            companyQuotaView.isHidden = false
        } else {
            companyQuotaView.isHidden = true
        }
        quotaStack.isHidden = codexQuotaView.isHidden && companyQuotaView.isHidden
    }

    private func captureStatusEffects(in snapshot: WorkStatusSnapshot) {
        for item in snapshot.items {
            if let previous = lastStatuses[item.id], previous != item.status {
                if item.status == .completed {
                    pendingSweepColors[item.id] = .systemGreen
                } else if previous.requiresAttention, item.status.isActiveWork {
                    pendingSweepColors[item.id] = .systemBlue
                }
            }
            lastStatuses[item.id] = item.status
        }
        let currentIDs = Set(snapshot.items.map(\.id))
        lastStatuses = lastStatuses.filter { currentIDs.contains($0.key) }
    }

    private func panelLayout(for snapshot: WorkStatusSnapshot) -> WorkPanelLayout {
        let grouped: [WorkSection: [WorkItem]] = Dictionary(grouping: snapshot.items) { item in
            switch item.status {
            case .running: .active
            case .queued: .queued
            case .waiting, .failed, .stale: .needsUser
            case .completed, .idle: .recent
            }
        }
        if !didChooseDefaultSection {
            let preferred: [WorkSection] = [.needsUser, .active, .queued, .recent]
            if let first = preferred.first(where: { !(grouped[$0] ?? []).isEmpty }) {
                expandedSections = [first]
            }
            didChooseDefaultSection = true
        }

        var remainingRows = 7
        let sections = WorkSection.allCases.compactMap { section -> WorkSectionLayout? in
            guard let allItems = grouped[section], !allItems.isEmpty else { return nil }
            let expanded = section.isAlwaysExpanded || expandedSections.contains(section)
            let rowLimit = section.isAlwaysExpanded ? remainingRows : min(5, remainingRows)
            let visible = expanded ? Array(allItems.prefix(max(0, rowLimit))) : []
            remainingRows -= visible.count
            return WorkSectionLayout(
                section: section,
                totalCount: allItems.count,
                items: visible,
                isExpanded: expanded
            )
        }
        return WorkPanelLayout(sections: sections)
    }

    private func toggle(section: WorkSection) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
        if let latestSnapshot { update(snapshot: latestSnapshot) }
    }

    func windowWillClose(_ notification: Notification) {
        cancelPendingAutoCollapse()
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        floatingPanel.orderOut(nil)
        onVisibilityChanged?(false)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "AI 工作岛"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: DesktopPanelLayout.width, height: 166)
        panel.maxSize = NSSize(width: DesktopPanelLayout.width, height: 746)
        panel.setFrameAutosaveName("AIWorkStatusPanelFrame")

        let materialView = PanelBackgroundView()
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 22
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        materialView.onHoverChanged = { [weak self] isHovering in
            self?.setPanelHovering(isHovering)
        }
        panel.contentView = materialView

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusCapsule.setContentCompressionResistancePriority(.required, for: .horizontal)

        newConversationButton.image = NSImage(
            systemSymbolName: "plus.circle.fill",
            accessibilityDescription: "新建 Codex 会话"
        )
        newConversationButton.isBordered = false
        newConversationButton.contentTintColor = .controlAccentColor
        newConversationButton.target = self
        newConversationButton.action = #selector(newConversation)
        newConversationButton.toolTip = "新建 Codex 会话"
        newConversationButton.setAccessibilityLabel("新建 Codex 会话")
        newConversationButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = NSStackView(views: [titleLabel, NSView(), statusCapsule, newConversationButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        quotaStack.setViews([codexQuotaView, companyQuotaView], in: .leading)
        quotaStack.orientation = .horizontal
        quotaStack.alignment = .centerY
        quotaStack.distribution = .fillEqually
        quotaStack.spacing = 8
        quotaStack.heightAnchor.constraint(equalToConstant: 34).isActive = true

        itemStack.orientation = .vertical
        itemStack.alignment = .width
        itemStack.spacing = 6
        itemStack.distribution = .fill

        footerLabel.font = .systemFont(ofSize: 10)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingMiddle

        let contentStack = NSStackView(views: [header, quotaStack, itemStack, footerLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 11
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 30),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: materialView.bottomAnchor, constant: -12),
        ])
    }

    @objc private func newConversation() {
        onNewConversationSelected?()
    }

    @objc private func minimizeToFloatingButton() {
        guard !isMinimizedToFloatingButton else { return }
        cancelPendingAutoCollapse()
        isHoverExpanded = false
        isMinimizedToFloatingButton = true
        positionFloatingPanelIfNeeded()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            panel.orderOut(nil)
            applyDisplayMode(hoverExpanded: false)
            floatingPanel.orderFrontRegardless()
            return
        }

        floatingPanel.alphaValue = 0
        floatingPanel.orderFrontRegardless()
        floatingButtonView.playEntrance()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.20
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            floatingPanel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self else { return }
            // Hover can restore the panel before this shrinking animation finishes.
            // Do not let the stale completion hide the newly restored panel.
            guard DesktopFloatingPanelTransition.shouldFinishMinimizing(
                isMinimizedToFloatingButton: isMinimizedToFloatingButton
            ) else {
                panel.alphaValue = 1
                return
            }
            panel.orderOut(nil)
            panel.alphaValue = 1
            applyDisplayMode(hoverExpanded: false)
        }
    }

    private func configureFloatingPanel() {
        floatingPanel.isFloatingPanel = true
        floatingPanel.level = .floating
        floatingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floatingPanel.hidesOnDeactivate = false
        floatingPanel.isOpaque = false
        floatingPanel.backgroundColor = .clear
        floatingPanel.hasShadow = true
        floatingPanel.animationBehavior = .utilityWindow
        let canvas = NSView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.canvasSize))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.clear.cgColor
        floatingButtonView.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(floatingButtonView)
        NSLayoutConstraint.activate([
            floatingButtonView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            floatingButtonView.centerYAnchor.constraint(equalTo: canvas.centerYAnchor),
            floatingButtonView.widthAnchor.constraint(equalToConstant: DesktopFloatingButtonLayout.size.width),
            floatingButtonView.heightAnchor.constraint(equalToConstant: DesktopFloatingButtonLayout.size.height),
        ])
        floatingPanel.contentView = canvas
        floatingButtonView.onActivate = { [weak self] in
            self?.activateFloatingButton(hoverExpanded: false)
        }
        floatingButtonView.onHoverEntered = { [weak self] in
            self?.activateFloatingButton(hoverExpanded: true)
        }
    }

    private func activateFloatingButton(hoverExpanded: Bool) {
        guard isMinimizedToFloatingButton else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            isMinimizedToFloatingButton = false
            isHoverExpanded = hoverExpanded
            applyDisplayMode(hoverExpanded: hoverExpanded)
            floatingPanel.orderOut(nil)
            panel.orderFrontRegardless()
            refreshPanelHoverState()
            return
        }

        isMinimizedToFloatingButton = false
        isHoverExpanded = hoverExpanded
        applyDisplayMode(hoverExpanded: hoverExpanded)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        refreshPanelHoverState()
        floatingButtonView.playExit()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            floatingPanel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            floatingPanel.orderOut(nil)
            floatingPanel.alphaValue = 1
        }
    }

    private func setPanelHovering(_ isHovering: Bool) {
        isPanelHovered = isHovering
        if isHovering {
            cancelPendingAutoCollapse()
            return
        }
        scheduleAutoCollapseIfNeeded()
    }

    private func refreshPanelHoverState() {
        guard let contentView = panel.contentView else { return }
        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = contentView.convert(windowPoint, from: nil)
        setPanelHovering(contentView.bounds.contains(point))
    }

    private func scheduleAutoCollapseIfNeeded() {
        guard DesktopFloatingHoverBehavior.shouldAutoCollapse(
            isHoverExpanded: isHoverExpanded,
            isPanelHovered: isPanelHovered,
            isInteractionActive: isConversationEditing
        ) else { return }
        cancelPendingAutoCollapse()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  DesktopFloatingHoverBehavior.shouldAutoCollapse(
                    isHoverExpanded: isHoverExpanded,
                    isPanelHovered: isPanelHovered,
                    isInteractionActive: isConversationEditing
                  ) else { return }
            minimizeToFloatingButton()
        }
        pendingAutoCollapse = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopFloatingHoverBehavior.collapseDelay,
            execute: workItem
        )
    }

    private func cancelPendingAutoCollapse() {
        pendingAutoCollapse?.cancel()
        pendingAutoCollapse = nil
    }

    private func positionFloatingPanelIfNeeded() {
        guard !didPositionFloatingPanel else { return }
        let size = DesktopFloatingButtonLayout.canvasSize
        if panel.frame.origin != .zero {
            floatingPanel.setFrameOrigin(NSPoint(
                x: panel.frame.maxX - size.width,
                y: panel.frame.maxY - size.height
            ))
        } else if let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main {
            let frame = screen.visibleFrame
            floatingPanel.setFrameOrigin(NSPoint(
                x: frame.maxX - size.width - 20,
                y: frame.maxY - size.height - 20
            ))
        }
        didPositionFloatingPanel = true
    }
}

@MainActor
final class FloatingStatusButtonView: NSVisualEffectView {
    var onActivate: (() -> Void)?
    var onHoverEntered: (() -> Void)?

    private let statusDot = NSView()
    private let statusHalo = NSView()
    private let statusLabel = NSTextField(labelWithString: "空闲")
    private let ambientLayer = CAGradientLayer()
    private let borderContainerLayer = CALayer()
    private let borderGradientLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()
    private let rippleLayer = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let glassHighlightLayer = CAGradientLayer()
    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var didDrag = false
    private var trackingAreaReference: NSTrackingArea?
    private var currentTintColor = NSColor.controlAccentColor
    private var currentPresentation: DesktopFloatingButtonPresentation?
    private var isHovering = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        alphaValue = 0.96
        wantsLayer = true
        layer?.cornerRadius = DesktopFloatingButtonLayout.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75
        layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.52).cgColor
        layer?.masksToBounds = true

        glassHighlightLayer.startPoint = CGPoint(x: 0.08, y: 0)
        glassHighlightLayer.endPoint = CGPoint(x: 0.92, y: 1)
        glassHighlightLayer.colors = [
            NSColor.white.withAlphaComponent(0.24).cgColor,
            NSColor.systemBlue.withAlphaComponent(0.08).cgColor,
            NSColor.clear.cgColor,
        ]
        glassHighlightLayer.locations = [0, 0.42, 1]
        layer?.addSublayer(glassHighlightLayer)

        ambientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        ambientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        ambientLayer.locations = [0, 0.48, 1]
        ambientLayer.opacity = 0
        layer?.addSublayer(ambientLayer)

        borderGradientLayer.type = .conic
        borderGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        borderGradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        borderContainerLayer.opacity = 0
        borderMaskLayer.fillColor = NSColor.clear.cgColor
        borderMaskLayer.strokeColor = NSColor.white.cgColor
        borderMaskLayer.lineWidth = 1.15
        borderContainerLayer.mask = borderMaskLayer
        borderContainerLayer.addSublayer(borderGradientLayer)
        layer?.addSublayer(borderContainerLayer)

        sheenLayer.startPoint = CGPoint(x: 0, y: 0.5)
        sheenLayer.endPoint = CGPoint(x: 1, y: 0.5)
        sheenLayer.locations = [0, 0.5, 1]
        sheenLayer.opacity = 0
        layer?.addSublayer(sheenLayer)

        statusHalo.wantsLayer = true
        statusHalo.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusHalo)

        rippleLayer.fillColor = NSColor.clear.cgColor
        rippleLayer.lineWidth = 1.25
        rippleLayer.opacity = 0
        statusHalo.layer?.addSublayer(rippleLayer)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = DesktopFloatingButtonLayout.statusDotSize / 2
        statusDot.translatesAutoresizingMaskIntoConstraints = false
        statusHalo.addSubview(statusDot)

        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.92)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusHalo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            statusHalo.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusHalo.widthAnchor.constraint(equalToConstant: 20),
            statusHalo.heightAnchor.constraint(equalToConstant: 20),
            statusDot.centerXAnchor.constraint(equalTo: statusHalo.centerXAnchor),
            statusDot.centerYAnchor.constraint(equalTo: statusHalo.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: DesktopFloatingButtonLayout.statusDotSize),
            statusDot.heightAnchor.constraint(equalToConstant: DesktopFloatingButtonLayout.statusDotSize),
            statusLabel.leadingAnchor.constraint(equalTo: statusHalo.trailingAnchor, constant: 4),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
        ])
        update(items: [], latestCompleted: nil)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        glassHighlightLayer.frame = bounds
        ambientLayer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 2, height: bounds.height)
        borderContainerLayer.frame = bounds
        borderMaskLayer.frame = bounds
        borderMaskLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.8, dy: 0.8),
            cornerWidth: DesktopFloatingButtonLayout.cornerRadius - 0.8,
            cornerHeight: DesktopFloatingButtonLayout.cornerRadius - 0.8,
            transform: nil
        )
        let gradientSide = hypot(bounds.width, bounds.height)
        borderGradientLayer.frame = CGRect(
            x: bounds.midX - gradientSide / 2,
            y: bounds.midY - gradientSide / 2,
            width: gradientSide,
            height: gradientSide
        )
        rippleLayer.frame = statusHalo.bounds
        rippleLayer.path = CGPath(
            ellipseIn: statusHalo.bounds.insetBy(dx: 1.5, dy: 1.5),
            transform: nil
        )
        sheenLayer.frame = CGRect(x: -36, y: 0, width: 36, height: bounds.height)
    }

    func update(snapshot: WorkStatusSnapshot) {
        update(
            items: snapshot.items,
            latestCompleted: WorkStatusHub.latestCompletedOpenableItem(from: snapshot.items)
        )
    }

    private func update(items: [WorkItem], latestCompleted: WorkItem?) {
        let presentation = DesktopFloatingButtonPresentation.make(
            items: items,
            latestCompleted: latestCompleted
        )
        guard presentation != currentPresentation else { return }
        let shouldAnimate = DesktopFloatingButtonMotion.shouldAnimateTransition(
            from: currentPresentation,
            to: presentation,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        currentPresentation = presentation
        if shouldAnimate {
            let push = CATransition()
            push.type = .push
            push.subtype = .fromTop
            push.duration = 0.26
            push.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            statusLabel.layer?.add(push, forKey: "statusTextPush")
        }
        currentTintColor = presentation.tintColor
        statusLabel.stringValue = presentation.displayText
        statusDot.layer?.backgroundColor = presentation.tintColor.cgColor
        statusDot.layer?.shadowColor = presentation.tintColor.cgColor
        statusDot.layer?.shadowOpacity = 0.55
        statusDot.layer?.shadowRadius = 4
        statusDot.layer?.shadowOffset = .zero
        updatePulse(enabled: presentation.pulses)
        updateAmbientMotion(enabled: presentation.pulses, tintColor: presentation.tintColor)
        if shouldAnimate { animateStatusTransition(tintColor: presentation.tintColor) }
        setAccessibilityLabel(presentation.accessibilityLabel)
        toolTip = presentation.accessibilityLabel
    }

    private func updatePulse(enabled: Bool) {
        statusDot.layer?.removeAnimation(forKey: "statusPulse")
        rippleLayer.removeAnimation(forKey: "runningRipple")
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.48
        opacity.toValue = 1.0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.84
        scale.toValue = 1.16
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 0.9
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        statusDot.layer?.add(group, forKey: "statusPulse")

        rippleLayer.strokeColor = currentTintColor.withAlphaComponent(0.70).cgColor
        let rippleScale = CABasicAnimation(keyPath: "transform.scale")
        rippleScale.fromValue = 0.45
        rippleScale.toValue = 1.08
        let rippleOpacity = CAKeyframeAnimation(keyPath: "opacity")
        rippleOpacity.values = [0, 0.65, 0]
        rippleOpacity.keyTimes = [0, 0.18, 1]
        let ripple = CAAnimationGroup()
        ripple.animations = [rippleScale, rippleOpacity]
        ripple.duration = 1.35
        ripple.repeatCount = .infinity
        ripple.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(ripple, forKey: "runningRipple")
    }

    private func updateAmbientMotion(enabled: Bool, tintColor: NSColor) {
        ambientLayer.removeAnimation(forKey: "ambientDrift")
        borderGradientLayer.removeAnimation(forKey: "borderOrbit")
        ambientLayer.opacity = 0
        borderContainerLayer.opacity = 0
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        ambientLayer.colors = [
            tintColor.withAlphaComponent(0).cgColor,
            tintColor.withAlphaComponent(0.17).cgColor,
            tintColor.withAlphaComponent(0).cgColor,
        ]
        ambientLayer.opacity = 1
        let drift = CABasicAnimation(keyPath: "transform.translation.x")
        drift.fromValue = -bounds.width * 0.35
        drift.toValue = bounds.width * 0.35
        drift.duration = DesktopFloatingButtonMotion.ambientCycleDuration
        drift.autoreverses = true
        drift.repeatCount = .infinity
        drift.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ambientLayer.add(drift, forKey: "ambientDrift")

        borderGradientLayer.colors = [
            tintColor.withAlphaComponent(0).cgColor,
            tintColor.withAlphaComponent(0).cgColor,
            tintColor.withAlphaComponent(0.14).cgColor,
            tintColor.withAlphaComponent(0.78).cgColor,
            tintColor.withAlphaComponent(0.14).cgColor,
            tintColor.withAlphaComponent(0).cgColor,
            tintColor.withAlphaComponent(0).cgColor,
        ]
        borderGradientLayer.locations = [0, 0.54, 0.68, 0.78, 0.88, 0.98, 1]
        borderContainerLayer.opacity = 0.92
        let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
        orbit.fromValue = 0
        orbit.toValue = CGFloat.pi * 2
        orbit.duration = DesktopFloatingButtonMotion.borderCycleDuration
        orbit.repeatCount = .infinity
        orbit.timingFunction = CAMediaTimingFunction(name: .linear)
        borderGradientLayer.add(orbit, forKey: "borderOrbit")
    }

    private func animateStatusTransition(tintColor: NSColor) {
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = [1.0, 1.045, 0.992, 1.0]
        bounce.keyTimes = [0, 0.34, 0.68, 1]
        bounce.duration = DesktopFloatingButtonMotion.transitionDuration
        bounce.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        layer?.add(bounce, forKey: "statusBounce")

        let dotPop = CAKeyframeAnimation(keyPath: "transform.scale")
        dotPop.values = [0.55, 1.45, 0.88, 1.0]
        dotPop.keyTimes = [0, 0.32, 0.70, 1]
        dotPop.duration = 0.46
        dotPop.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        statusDot.layer?.add(dotPop, forKey: "statusDotPop")

        rippleLayer.strokeColor = tintColor.withAlphaComponent(0.80).cgColor
        let burstScale = CABasicAnimation(keyPath: "transform.scale")
        burstScale.fromValue = 0.35
        burstScale.toValue = 1.15
        let burstOpacity = CAKeyframeAnimation(keyPath: "opacity")
        burstOpacity.values = [0, 0.9, 0]
        burstOpacity.keyTimes = [0, 0.18, 1]
        let burst = CAAnimationGroup()
        burst.animations = [burstScale, burstOpacity]
        burst.duration = 0.58
        burst.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(burst, forKey: "statusBurst")

        sheenLayer.colors = [
            tintColor.withAlphaComponent(0).cgColor,
            tintColor.withAlphaComponent(0.34).cgColor,
            tintColor.withAlphaComponent(0).cgColor,
        ]
        let travel = CABasicAnimation(keyPath: "transform.translation.x")
        travel.fromValue = 0
        travel.toValue = bounds.width + 72
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.9, 0.9, 0]
        opacity.keyTimes = [0, 0.18, 0.72, 1]
        let sweep = CAAnimationGroup()
        sweep.animations = [travel, opacity]
        sweep.duration = DesktopFloatingButtonMotion.transitionDuration
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        sheenLayer.add(sweep, forKey: "statusSheen")

        let borderFlash = CAKeyframeAnimation(keyPath: "borderColor")
        borderFlash.values = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            tintColor.withAlphaComponent(0.80).cgColor,
            NSColor.white.withAlphaComponent(0.14).cgColor,
        ]
        borderFlash.keyTimes = [0, 0.38, 1]
        borderFlash.duration = 0.72
        layer?.add(borderFlash, forKey: "statusBorderFlash")
    }

    func playEntrance() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.62
        scale.toValue = 1
        scale.mass = 0.85
        scale.stiffness = 330
        scale.damping = 22
        scale.initialVelocity = 2.2
        scale.duration = DesktopFloatingButtonMotion.entranceDuration
        layer?.add(scale, forKey: "floatingEntranceScale")

        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = -22
        slide.toValue = 0
        slide.duration = 0.32
        slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer?.add(slide, forKey: "floatingEntranceSlide")
    }

    func playExit() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 0.78
        scale.duration = 0.22
        scale.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer?.add(scale, forKey: "floatingExitScale")
    }

    func motionSnapshot() -> DesktopFloatingButtonMotionSnapshot {
        DesktopFloatingButtonMotionSnapshot(
            root: Set(layer?.animationKeys() ?? []),
            statusDot: Set(statusDot.layer?.animationKeys() ?? []),
            ripple: Set(rippleLayer.animationKeys() ?? []),
            ambient: Set(ambientLayer.animationKeys() ?? []),
            border: Set(borderGradientLayer.animationKeys() ?? []),
            sheen: Set(sheenLayer.animationKeys() ?? [])
        )
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.push()
        setHovering(true)
        handleHoverEntered()
    }

    func handleHoverEntered() {
        onHoverEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        setHovering(false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        didDrag = false
        setScale(0.96)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation,
              let origin = windowOriginAtMouseDown,
              let window else { return }
        let current = NSEvent.mouseLocation
        let deltaX = current.x - start.x
        let deltaY = current.y - start.y
        if hypot(deltaX, deltaY) > 3 { didDrag = true }
        guard didDrag else { return }
        setScale(1)
        window.setFrameOrigin(NSPoint(x: origin.x + deltaX, y: origin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        setScale(isHovering ? 1.025 : 1)
        if !didDrag { onActivate?() }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        didDrag = false
    }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    private func setHovering(_ hovering: Bool) {
        isHovering = hovering
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = hovering ? 1 : 0.92
        }
        layer?.borderColor = hovering
            ? currentTintColor.withAlphaComponent(0.48).cgColor
            : NSColor.white.withAlphaComponent(0.14).cgColor
        let targetScale: CGFloat = hovering && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? 1.025
            : 1
        setScale(targetScale)
    }

    private func setScale(_ scale: CGFloat) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
}

@MainActor
private final class WorkSectionHeaderView: NSView {
    var onToggle: (() -> Void)?

    init(title: String, count: Int, expanded: Bool, collapsible: Bool = true) {
        super.init(frame: .zero)
        let button = NSButton(
            title: collapsible ? "\(expanded ? "▾" : "▸")  \(title)" : title,
            target: self,
            action: #selector(toggle)
        )
        button.isBordered = false
        button.isEnabled = collapsible
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.alignment = .left
        let countLabel = NSTextField(labelWithString: "\(count)")
        countLabel.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        countLabel.textColor = .tertiaryLabelColor
        let row = NSStackView(views: [button, NSView(), countLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 16),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    @objc private func toggle() { onToggle?() }
}

@MainActor
private final class DesktopQuotaSummaryView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private var displayedTitle = ""
    private var displayedValue = ""
    private var displayedPercent: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        valueLabel.alignment = .right
        valueLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleLabel, NSView(), valueLabel])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(title: String, value: String, remainingPercent: Int?) {
        guard displayedTitle != title
                || displayedValue != value
                || displayedPercent != remainingPercent else {
            return
        }
        displayedTitle = title
        displayedValue = value
        displayedPercent = remainingPercent
        titleLabel.stringValue = title
        valueLabel.stringValue = value

        if let remainingPercent, remainingPercent <= 20 {
            valueLabel.textColor = .systemRed
        } else if let remainingPercent, remainingPercent < 50 {
            valueLabel.textColor = .systemOrange
        } else {
            valueLabel.textColor = remainingPercent == nil ? .tertiaryLabelColor : .labelColor
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(title)：\(value)")
    }
}

@MainActor
private final class StatusCapsuleView: NSView {
    private let label = NSTextField(labelWithString: "正在读取…")
    private var currentText = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.30).cgColor
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(text: String, color: NSColor) {
        guard currentText != text else { return }
        currentText = text
        label.stringValue = text
        label.textColor = color
        layer?.backgroundColor = color.withAlphaComponent(0.16).cgColor
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.92
        spring.toValue = 1
        spring.stiffness = 360
        spring.damping = 25
        spring.duration = min(0.38, spring.settlingDuration)
        layer?.add(spring, forKey: "capsuleMorph")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.45
        fade.toValue = 1
        fade.duration = 0.18
        layer?.add(fade, forKey: "capsuleFade")
    }
}

@MainActor
private final class WorkItemRowView: NSVisualEffectView, NSTextFieldDelegate {
    var onSelected: (() -> Void)?
    var onDetailsSelected: (() -> Void)?
    var onPromptSubmitted: ((String) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?
    var onOutputSelected: (() -> Void)? {
        didSet { outputButton.isHidden = onOutputSelected == nil }
    }

    private let actions = NSStackView()
    private let outputButton = NSButton()
    private let promptField = NSTextField(string: "")
    private let sendButton = NSButton()
    private let conversationStatusLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?

    init(item: WorkItem, lastAssistantResult: String? = nil) {
        super.init(frame: .zero)
        material = .sidebar
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.12).cgColor
        layer?.masksToBounds = true

        let indicator = NSView()
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = item.status.color.cgColor
        indicator.layer?.cornerRadius = 4
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 8),
            indicator.heightAnchor.constraint(equalToConstant: 8),
        ])

        let title = NSTextField(labelWithString: item.displayTitle)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detailText = item.phase.map { "\($0) · \(item.displayDetail)" } ?? item.displayDetail
        let detail = NSTextField(labelWithString: detailText)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.maximumNumberOfLines = 1
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [title, detail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let status = NSTextField(labelWithString: item.status.chineseTitle)
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = item.status.color
        status.alignment = .right
        status.setContentCompressionResistancePriority(.required, for: .horizontal)

        outputButton.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "打开产出")
        outputButton.isBordered = false
        outputButton.toolTip = "打开产出"
        outputButton.target = self
        outputButton.action = #selector(openOutput)
        let detailsButton = actionButton(symbol: "info.circle", toolTip: "查看详情")
        detailsButton.target = self
        detailsButton.action = #selector(showDetails)
        actions.setViews([outputButton, detailsButton], in: .leading)
        actions.orientation = .horizontal
        actions.spacing = 3
        actions.alphaValue = 0
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        let mainRow = NSStackView(views: [indicator, textStack, NSView(), status, actions])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 8
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        if item.id.hasPrefix("codex:") {
            conversationStatusLabel.stringValue = "上轮：\(lastAssistantResult ?? "暂无可显示结果")"
            conversationStatusLabel.font = .systemFont(ofSize: 10)
            conversationStatusLabel.textColor = .tertiaryLabelColor
            conversationStatusLabel.lineBreakMode = .byTruncatingTail
            conversationStatusLabel.maximumNumberOfLines = 1
            conversationStatusLabel.toolTip = lastAssistantResult
            conversationStatusLabel.setContentCompressionResistancePriority(
                .defaultLow,
                for: .horizontal
            )

            promptField.placeholderString = "继续该项目…"
            promptField.font = .systemFont(ofSize: 11)
            promptField.focusRingType = .none
            promptField.delegate = self
            promptField.target = self
            promptField.action = #selector(submitPrompt)
            promptField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            sendButton.image = NSImage(
                systemSymbolName: "arrow.up.circle.fill",
                accessibilityDescription: "继续该项目"
            )
            sendButton.isBordered = false
            sendButton.contentTintColor = .controlAccentColor
            sendButton.target = self
            sendButton.action = #selector(submitPrompt)
            sendButton.toolTip = "继续该项目"

            let inputRow = NSStackView(views: [promptField, sendButton])
            inputRow.orientation = .horizontal
            inputRow.alignment = .centerY
            inputRow.spacing = 5
            sendButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

            let stack = NSStackView(views: [mainRow, conversationStatusLabel, inputRow])
            stack.orientation = .vertical
            stack.alignment = .width
            stack.spacing = 4
            stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 96),
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            ])
        } else {
            addSubview(mainRow)
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: 56),
                mainRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
                mainRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                mainRow.centerYAnchor.constraint(
                    equalTo: centerYAnchor,
                    constant: item.phaseCount == nil ? 0 : -2
                ),
            ])
        }

        if let count = item.phaseCount, count > 0 {
            let progress = StageProgressView(
                count: count,
                current: min(max(item.phaseIndex ?? 0, 0), count),
                color: item.status.color
            )
            progress.translatesAutoresizingMaskIntoConstraints = false
            addSubview(progress)
            NSLayoutConstraint.activate([
                progress.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 28),
                progress.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
                progress.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
                progress.heightAnchor.constraint(equalToConstant: 3),
            ])
        }
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) { setHovering(true) }
    override func mouseExited(with event: NSEvent) { setHovering(false) }
    override func mouseUp(with event: NSEvent) { onSelected?() }

    func playSuccessSweep(color: NSColor) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let sweep = CAGradientLayer()
        sweep.frame = bounds.insetBy(dx: -bounds.width, dy: 0)
        sweep.colors = [
            NSColor.clear.cgColor,
            color.withAlphaComponent(0.30).cgColor,
            NSColor.clear.cgColor,
        ]
        sweep.startPoint = CGPoint(x: 0, y: 0.5)
        sweep.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(sweep)
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = -bounds.width
        move.toValue = bounds.width
        move.duration = 0.72
        move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { sweep.removeFromSuperlayer() }
        sweep.add(move, forKey: "successSweep")
        CATransaction.commit()
    }

    func updateConversationStatus(_ text: String, isBusy: Bool) {
        conversationStatusLabel.stringValue = text
        conversationStatusLabel.textColor = isBusy ? .controlAccentColor : .secondaryLabelColor
        promptField.isEnabled = !isBusy
        sendButton.isEnabled = !isBusy
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        onEditingChanged?(true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        onEditingChanged?(false)
    }

    private func setHovering(_ hovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            actions.animator().alphaValue = hovering ? 1 : 0
        }
        layer?.borderColor = (hovering ? NSColor.controlAccentColor : NSColor.white)
            .withAlphaComponent(hovering ? 0.50 : 0.16).cgColor
        layer?.backgroundColor = (hovering ? NSColor.controlAccentColor : NSColor.windowBackgroundColor)
            .withAlphaComponent(hovering ? 0.12 : 0.12).cgColor
    }

    private func actionButton(symbol: String, toolTip: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.isBordered = false
        button.toolTip = toolTip
        return button
    }

    @objc private func openOutput() { onOutputSelected?() }
    @objc private func showDetails() { onDetailsSelected?() }
    @objc private func submitPrompt() {
        let prompt = promptField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, promptField.isEnabled else { return }
        promptField.stringValue = ""
        onPromptSubmitted?(prompt)
    }
}

@MainActor
private final class StageProgressView: NSView {
    init(count: Int, current: Int, color: NSColor) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for index in 1...count {
            let segment = NSView()
            segment.wantsLayer = true
            segment.layer?.cornerRadius = 1.5
            segment.layer?.backgroundColor = (index <= current ? color : NSColor.separatorColor)
                .withAlphaComponent(index <= current ? 0.75 : 0.30).cgColor
            stack.addArrangedSubview(segment)
        }
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class PanelBackgroundView: NSVisualEffectView {
    var onHoverChanged: ((Bool) -> Void)?
    private let tintLayer = CAGradientLayer()
    private let highlightLayer = CAGradientLayer()
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        tintLayer.startPoint = CGPoint(x: 0, y: 0)
        tintLayer.endPoint = CGPoint(x: 1, y: 1)
        highlightLayer.startPoint = CGPoint(x: 0.15, y: 0)
        highlightLayer.endPoint = CGPoint(x: 0.85, y: 1)
        highlightLayer.locations = [0, 0.35, 1]
        layer?.addSublayer(tintLayer)
        layer?.addSublayer(highlightLayer)
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func layout() {
        super.layout()
        tintLayer.frame = bounds
        highlightLayer.frame = bounds
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    private func updateColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = isDark ? NSColor.black : NSColor.white
        tintLayer.colors = [
            base.withAlphaComponent(isDark ? 0.34 : 0.38).cgColor,
            NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.12 : 0.08).cgColor,
            base.withAlphaComponent(isDark ? 0.24 : 0.28).cgColor,
        ]
        highlightLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.20 : 0.54).cgColor,
            NSColor.white.withAlphaComponent(isDark ? 0.06 : 0.20).cgColor,
            NSColor.clear.cgColor,
        ]
        layer?.backgroundColor = base.withAlphaComponent(0.10).cgColor
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(isDark ? 0.28 : 0.52).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.42 : 0.18).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 18
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }
}

private extension WorkItemStatus {
    var chineseTitle: String {
        switch self {
        case .running: "执行中"
        case .queued: "等待查询"
        case .waiting: "等待你"
        case .failed: "异常"
        case .completed: "已完成"
        case .idle: "空闲"
        case .stale: "失联"
        }
    }

    var color: NSColor {
        switch self {
        case .running: .systemBlue
        case .queued: .systemIndigo
        case .waiting: .systemOrange
        case .failed, .stale: .systemRed
        case .completed: .systemGreen
        case .idle: .secondaryLabelColor
        }
    }
}
