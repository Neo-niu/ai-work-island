import AppKit
import CodexTouchBarCore
import QuartzCore

enum DesktopPanelMode: Equatable {
    case desktopWidget
    case floating
}

enum DesktopPanelLayout {
    static let width: CGFloat = 372

    static func contentSize(visibleItemCount: Int, sectionCount: Int = 0) -> NSSize {
        let height = CGFloat(154 + max(1, visibleItemCount) * 62 + sectionCount * 22)
        return NSSize(width: width, height: min(height, 620))
    }
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

    init(_ item: WorkItem) {
        id = item.id
        title = item.displayTitle
        detail = item.displayDetail
        status = item.status
        outputPath = item.outputPath
        openURL = item.openURL
        phase = item.phase
        phaseIndex = item.phaseIndex
        phaseCount = item.phaseCount
    }
}

struct DesktopPanelContentSignature: Equatable {
    let items: [DesktopPanelItemPresentation]
    let automationIssues: [String]
    let layoutTokens: [String]

    init(snapshot: WorkStatusSnapshot, layoutTokens: [String]) {
        items = snapshot.items.map(DesktopPanelItemPresentation.init)
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
    var onVoiceMemoSelected: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    private let panel: NSPanel
    private let titleLabel = NSTextField(labelWithString: "AI 工作状态")
    private let statusCapsule = StatusCapsuleView()
    private let voiceMemoButton = NSButton(title: "录音", target: nil, action: nil)
    private let codexQuotaView = DesktopQuotaSummaryView()
    private let companyQuotaView = DesktopQuotaSummaryView()
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

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesktopPanelLayout.width, height: 180),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()
        configurePanel()
    }

    var isVisible: Bool { panel.isVisible }

    func setDisplayMode(_ mode: DesktopPanelMode) {
        switch mode {
        case .desktopWidget:
            panel.styleMask.remove(.closable)
            panel.isFloatingPanel = false
            panel.level = NSWindow.Level(
                rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 2
            )
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
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
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func update(snapshot: WorkStatusSnapshot) {
        latestSnapshot = snapshot
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
            layoutTokens: visibleIDs
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
            statusCapsule.update(text: "\(running) 运行 · \(queued) 等待查询", color: .systemIndigo)
        } else {
            statusCapsule.update(text: "\(running) 运行 · 共 \(snapshot.items.count) 项", color: .systemBlue)
        }

        itemStack.arrangedSubviews.forEach {
            itemStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

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
                    let row = WorkItemRowView(item: item)
                    row.onSelected = { [weak self] in self?.onItemSelected?(item) }
                    row.onDetailsSelected = { [weak self] in self?.onItemDetailsSelected?(item) }
                    row.onOutputSelected = item.outputPath == nil ? nil : { [weak self] in
                        self?.onItemOutputSelected?(item)
                    }
                    itemStack.addArrangedSubview(row)
                    if let color = pendingSweepColors.removeValue(forKey: item.id) {
                        DispatchQueue.main.async { row.playSuccessSweep(color: color) }
                    }
                }
            }
        }

        let hiddenCount = snapshot.items.count - layout.rowCount
        let issueText = snapshot.automationIssues.isEmpty
            ? ""
            : " · 状态文件异常 \(snapshot.automationIssues.count)"
        let hiddenText = hiddenCount > 0 ? " · 另有 \(hiddenCount) 项" : ""
        let latestMeaningfulUpdate = snapshot.items.map(\.updatedAt).max() ?? snapshot.refreshedAt
        footerLabel.stringValue = "更新于 \(Self.timeFormatter.string(from: latestMeaningfulUpdate))\(hiddenText)\(issueText)"
        footerLabel.textColor = snapshot.automationIssues.isEmpty ? .tertiaryLabelColor : .systemRed

        if resizeImmediately {
            panel.setContentSize(DesktopPanelLayout.contentSize(
                visibleItemCount: layout.rowCount,
                sectionCount: layout.sections.count
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

            let sectionCount = panelLayout(for: snapshot).sections.count
            let contentSize = DesktopPanelLayout.contentSize(
                visibleItemCount: newRowCount,
                sectionCount: sectionCount
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
            value: codexText.isEmpty ? "暂不可用" : codexText,
            remainingPercent: codexLimits.map(\.remainingPercent).min()
        )

        if let quota = snapshot.companyQuota {
            companyQuotaView.update(
                title: "公司额度",
                value: String(format: "$%.2f · %d%%", quota.remainingUSD, quota.remainingPercent),
                remainingPercent: quota.remainingPercent
            )
        } else {
            companyQuotaView.update(title: "公司额度", value: "暂不可用", remainingPercent: nil)
        }
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
        onVisibilityChanged?(false)
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "AI 工作状态"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.minSize = NSSize(width: DesktopPanelLayout.width, height: 166)
        panel.maxSize = NSSize(width: DesktopPanelLayout.width, height: 666)
        panel.setFrameAutosaveName("AIWorkStatusPanelFrame")

        let materialView = PanelBackgroundView()
        materialView.wantsLayer = true
        materialView.layer?.cornerRadius = 14
        materialView.layer?.cornerCurve = .continuous
        materialView.layer?.masksToBounds = true
        panel.contentView = materialView

        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusCapsule.setContentCompressionResistancePriority(.required, for: .horizontal)

        voiceMemoButton.image = NSImage(
            systemSymbolName: "mic.circle.fill",
            accessibilityDescription: "开始语音备忘录录音"
        )
        voiceMemoButton.imagePosition = .imageLeading
        voiceMemoButton.bezelStyle = .recessed
        voiceMemoButton.font = .systemFont(ofSize: 11, weight: .semibold)
        voiceMemoButton.target = self
        voiceMemoButton.action = #selector(startVoiceMemo)
        voiceMemoButton.toolTip = "打开语音备忘录并立即开始；30 秒以上录音结束后自动生成会议纪要"
        voiceMemoButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let header = NSStackView(views: [titleLabel, NSView(), statusCapsule, voiceMemoButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let quotaStack = NSStackView(views: [codexQuotaView, companyQuotaView])
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    @objc private func startVoiceMemo() {
        onVoiceMemoSelected?()
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
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5

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

        let color: NSColor
        if let remainingPercent {
            if remainingPercent <= 20 {
                color = .systemRed
            } else if remainingPercent < 50 {
                color = .systemOrange
            } else {
                color = .controlAccentColor
            }
        } else {
            color = .tertiaryLabelColor
        }
        valueLabel.textColor = remainingPercent == nil ? .tertiaryLabelColor : .labelColor
        layer?.backgroundColor = color.withAlphaComponent(0.08).cgColor
        layer?.borderColor = color.withAlphaComponent(0.28).cgColor
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
        layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
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
private final class WorkItemRowView: NSVisualEffectView {
    var onSelected: (() -> Void)?
    var onDetailsSelected: (() -> Void)?
    var onOutputSelected: (() -> Void)? {
        didSet { outputButton.isHidden = onOutputSelected == nil }
    }

    private let actions = NSStackView()
    private let outputButton = NSButton()
    private var tracking: NSTrackingArea?

    init(item: WorkItem) {
        super.init(frame: .zero)
        material = .contentBackground
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
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

        let openButton = actionButton(symbol: "arrow.up.forward.app", toolTip: "打开任务")
        openButton.target = self
        openButton.action = #selector(openTask)
        outputButton.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "打开产出")
        outputButton.isBordered = false
        outputButton.toolTip = "打开产出"
        outputButton.target = self
        outputButton.action = #selector(openOutput)
        let detailsButton = actionButton(symbol: "info.circle", toolTip: "查看详情")
        detailsButton.target = self
        detailsButton.action = #selector(showDetails)
        actions.setViews([openButton, outputButton, detailsButton], in: .leading)
        actions.orientation = .horizontal
        actions.spacing = 3
        actions.alphaValue = 0
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [indicator, textStack, NSView(), status, actions])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 56),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -11),
            row.centerYAnchor.constraint(equalTo: centerYAnchor, constant: item.phaseCount == nil ? 0 : -2),
        ])

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

    private func setHovering(_ hovering: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            actions.animator().alphaValue = hovering ? 1 : 0
        }
        layer?.borderColor = (hovering ? NSColor.controlAccentColor : NSColor.separatorColor)
            .withAlphaComponent(hovering ? 0.42 : 0.45).cgColor
    }

    private func actionButton(symbol: String, toolTip: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.isBordered = false
        button.toolTip = toolTip
        return button
    }

    @objc private func openTask() { onSelected?() }
    @objc private func openOutput() { onOutputSelected?() }
    @objc private func showDetails() { onDetailsSelected?() }
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
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateColors()
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
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
