import AppKit
import CodexTouchBarCore
import QuartzCore

enum DesktopPanelMode: Equatable {
    case background
    case floating
}

enum DesktopContentMode: String, CaseIterable, Equatable {
    case clean
    case detailed

    var title: String {
        switch self {
        case .clean: "清爽模式"
        case .detailed: "详细模式"
        }
    }

    var conversationCardHeight: CGFloat { self == .clean ? 104 : 136 }
    var conversationExtraHeight: Int { self == .clean ? 42 : 74 }
    var conversationStatusLineCount: Int { self == .clean ? 1 : 3 }
    var conversationStatusFontSize: CGFloat { self == .clean ? 11 : 11.5 }
}

enum DesktopPanelWindowPolicy {
    static func floatsAboveFullScreen(
        mode: DesktopPanelMode,
        hoverExpanded: Bool
    ) -> Bool {
        mode == .floating || hoverExpanded
    }
}

enum DesktopWindowEdgeSnap {
    static let threshold: CGFloat = 18
    static let noInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    static func snappedFrame(
        _ frame: NSRect,
        in visibleFrame: NSRect,
        contentInsets: NSEdgeInsets = noInsets
    ) -> NSRect {
        var snapped = frame
        let visualMinX = frame.minX + contentInsets.left
        let visualMaxX = frame.maxX - contentInsets.right
        let visualMinY = frame.minY + contentInsets.bottom
        let visualMaxY = frame.maxY - contentInsets.top

        if abs(visualMinX - visibleFrame.minX) <= threshold {
            snapped.origin.x = visibleFrame.minX - contentInsets.left
        } else if abs(visualMaxX - visibleFrame.maxX) <= threshold {
            snapped.origin.x = visibleFrame.maxX - frame.width + contentInsets.right
        }

        if abs(visualMinY - visibleFrame.minY) <= threshold {
            snapped.origin.y = visibleFrame.minY - contentInsets.bottom
        } else if abs(visualMaxY - visibleFrame.maxY) <= threshold {
            snapped.origin.y = visibleFrame.maxY - frame.height + contentInsets.top
        }
        return snapped
    }
}

enum DesktopWindowVisibility {
    static func clampedFrame(
        _ frame: NSRect,
        in visibleFrame: NSRect,
        contentInsets: NSEdgeInsets = DesktopWindowEdgeSnap.noInsets
    ) -> NSRect {
        var clamped = frame
        let minimumX = visibleFrame.minX - contentInsets.left
        let maximumX = visibleFrame.maxX - frame.width + contentInsets.right
        let minimumY = visibleFrame.minY - contentInsets.bottom
        let maximumY = visibleFrame.maxY - frame.height + contentInsets.top
        clamped.origin.x = min(max(frame.origin.x, minimumX), maximumX)
        clamped.origin.y = min(max(frame.origin.y, minimumY), maximumY)
        return clamped
    }
}

enum DesktopPanelAnchorLayout {
    static func panelFrame(
        anchoredToFloatingPanel floatingFrame: NSRect,
        panelSize: NSSize
    ) -> NSRect {
        NSRect(
            x: floatingFrame.maxX - panelSize.width,
            y: floatingFrame.maxY - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func floatingFrame(
        anchoredToPanel panelFrame: NSRect,
        floatingSize: NSSize
    ) -> NSRect {
        NSRect(
            x: panelFrame.maxX - floatingSize.width,
            y: panelFrame.maxY - floatingSize.height,
            width: floatingSize.width,
            height: floatingSize.height
        )
    }
}

enum DesktopPanelLayout {
    static let width: CGFloat = 372
    static let contentHorizontalInset: CGFloat = 14
    static let workItemHorizontalInset: CGFloat = 11
    static let contentWidth = width - contentHorizontalInset * 2
    static let conversationContentWidth = contentWidth - workItemHorizontalInset * 2

    static func contentSize(
        visibleItemCount: Int,
        sectionCount: Int = 0,
        conversationItemCount: Int = 0,
        contentMode: DesktopContentMode = .clean
    ) -> NSSize {
        let baseHeight = 184
        let itemHeight = max(1, visibleItemCount) * 62
        let sectionHeight = sectionCount * 22
        let conversationHeight = conversationItemCount * contentMode.conversationExtraHeight
        let height = CGFloat(baseHeight + itemHeight + sectionHeight + conversationHeight)
        return NSSize(width: width, height: min(height, contentMode == .clean ? 700 : 720))
    }
}

enum DesktopPanelResizePolicy {
    static let minimumFrameSize = NSSize(width: 320, height: 260)
    static let maximumFrameSize = NSSize(width: 620, height: 746)

    static func clampedFrameSize(_ size: NSSize) -> NSSize {
        NSSize(
            width: min(max(size.width, minimumFrameSize.width), maximumFrameSize.width),
            height: min(max(size.height, minimumFrameSize.height), maximumFrameSize.height)
        )
    }

    static func automaticallyFittedContentSize(
        _ contentSize: NSSize,
        currentContentSize: NSSize,
        hasUserPreferredSize: Bool
    ) -> NSSize {
        NSSize(
            width: hasUserPreferredSize ? currentContentSize.width : contentSize.width,
            height: contentSize.height
        )
    }
}

enum DesktopPanelPalette {
    static let base = NSColor(srgbRed: 0x30 / 255, green: 0x32 / 255, blue: 0x37 / 255, alpha: 1)
    static let card = NSColor(srgbRed: 0x3A / 255, green: 0x3C / 255, blue: 0x42 / 255, alpha: 1)
    static let input = NSColor(srgbRed: 0x27 / 255, green: 0x29 / 255, blue: 0x2D / 255, alpha: 1)
    static let stroke = NSColor(srgbRed: 0x57 / 255, green: 0x5A / 255, blue: 0x61 / 255, alpha: 1)
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

    static func carousel(for snapshot: WorkStatusSnapshot) -> [Self] {
        let work = make(
            items: snapshot.items,
            latestCompleted: WorkStatusHub.latestCompletedOpenableItem(from: snapshot.items)
        )
        let hasPriorityStatus = snapshot.items.contains {
            $0.status == .waiting || $0.status == .failed || $0.status == .stale
        }
        guard !hasPriorityStatus else { return [work] }

        var pages = [work]
        if let quota = snapshot.companyQuota {
            let amount = quota.remainingUSD >= 10
                ? String(format: "$%.0f", quota.remainingUSD)
                : String(format: "$%.1f", quota.remainingUSD)
            pages.append(Self.quota(
                displayText: "公司 \(amount)",
                remainingPercent: quota.remainingPercent,
                normalTint: .systemPurple,
                accessibilityText: String(
                    format: "公司额度剩余$%.2f，剩余%d%%",
                    quota.remainingUSD,
                    quota.remainingPercent
                )
            ))
        } else {
            pages.append(Self(
                displayText: "公司 待配置",
                tintColor: .systemPurple,
                pulses: false,
                accessibilityLabel: "恢复 AI 工作岛；公司额度待配置，请在 Edge 登录公司模型平台"
            ))
        }
        if let limit = snapshot.codexShortTermLimit {
            pages.append(quota(
                displayText: "5时 \(limit.remainingPercent)%",
                remainingPercent: limit.remainingPercent,
                normalTint: .systemTeal,
                accessibilityText: "5小时额度剩余\(limit.remainingPercent)%"
            ))
        }
        if let limit = snapshot.codexWeeklyLimit {
            pages.append(quota(
                displayText: "周 \(limit.remainingPercent)%",
                remainingPercent: limit.remainingPercent,
                normalTint: .systemIndigo,
                accessibilityText: "周额度剩余\(limit.remainingPercent)%"
            ))
        }
        return pages
    }

    static func recordingGuardian(_ state: VoiceMemoGuardianState, now: Date = Date()) -> Self {
        let isSilent = state.phase == .silence
        return Self(
            displayText: state.displayText(at: now),
            tintColor: isSilent ? .systemOrange : .systemRed,
            pulses: !isSilent,
            accessibilityLabel: isSilent
                ? "语音备忘录可能已结束；\(state.displayText(at: now))"
                : "语音备忘录正在录音；\(state.displayText(at: now))"
        )
    }

    private static func quota(
        displayText: String,
        remainingPercent: Int,
        normalTint: NSColor,
        accessibilityText: String
    ) -> Self {
        let tintColor: NSColor
        if remainingPercent <= 20 {
            tintColor = .systemRed
        } else if remainingPercent < 50 {
            tintColor = .systemOrange
        } else {
            tintColor = normalTint
        }
        return Self(
            displayText: displayText,
            tintColor: tintColor,
            pulses: false,
            accessibilityLabel: "恢复 AI 工作岛；\(accessibilityText)"
        )
    }
}

enum DesktopFloatingButtonMotion {
    static let entranceDuration: TimeInterval = 0.42
    static let transitionDuration: TimeInterval = 0.62
    static let ambientCycleDuration: TimeInterval = 2.4
    static let borderCycleDuration: TimeInterval = 1.8
    static let carouselInterval: TimeInterval = 4

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
    static func shouldActivate(
        isMinimizedToFloatingButton: Bool,
        isFloatingPanelVisible: Bool
    ) -> Bool {
        // AppKit can keep an ordered-out/fully transparent NSPanel reporting
        // `isVisible == true`. The capsule itself is the authoritative hit target:
        // if it is visible, its click must be allowed to restore the main panel.
        isMinimizedToFloatingButton || isFloatingPanelVisible
    }

    static func shouldFinishMinimizing(isMinimizedToFloatingButton: Bool) -> Bool {
        isMinimizedToFloatingButton
    }
}

enum DesktopFloatingHoverBehavior {
    static let collapseDelay: TimeInterval = 0.5
    /// `mouseExited` can be missed by a borderless panel while AppKit changes
    /// the active responder. Reconcile against the real pointer location while
    /// the panel is hover-expanded so it cannot remain open indefinitely.
    static let hoverReconciliationInterval: TimeInterval = 0.1

    static func shouldAutoCollapse(
        isHoverExpanded: Bool,
        isPanelHovered: Bool
    ) -> Bool {
        isHoverExpanded && !isPanelHovered
    }

    /// Pointer reconciliation runs more frequently than the collapse delay.
    /// Once a leave has queued a collapse, further unchanged samples must not
    /// restart that delay indefinitely.
    static func shouldScheduleAutoCollapse(
        isHoverExpanded: Bool,
        isPanelHovered: Bool,
        hasPendingAutoCollapse: Bool
    ) -> Bool {
        shouldAutoCollapse(
            isHoverExpanded: isHoverExpanded,
            isPanelHovered: isPanelHovered
        ) && !hasPendingAutoCollapse
    }

    /// A cancelled DispatchWorkItem can still reach its closure. Only the
    /// currently scheduled request may clear the pending marker; otherwise an
    /// old callback could erase a newer leave-to-collapse request.
    static func isCurrentAutoCollapseRequest(
        firedRequestID: UInt,
        currentRequestID: UInt
    ) -> Bool {
        firedRequestID == currentRequestID
    }
}

enum DesktopCompletionReminderBehavior {
    static let revealDuration: TimeInterval = 4

    static func newlyCompletedItemIDs(
        previous: WorkStatusSnapshot?,
        current: WorkStatusSnapshot
    ) -> Set<String> {
        guard let previous else { return [] }
        let previousStatuses = Dictionary(uniqueKeysWithValues: previous.items.map { ($0.id, $0.status) })
        return Set(current.items.compactMap { item in
            guard previousStatuses[item.id]?.isActiveWork == true,
                  item.status == .waiting || item.status == .completed else { return nil }
            return item.id
        })
    }

    static func autoCollapseDelay(
        standardDelay: TimeInterval,
        completionRevealRemaining: TimeInterval
    ) -> TimeInterval {
        max(standardDelay, completionRevealRemaining)
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
    let recentActivity: String?
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
        recentActivity = item.recentActivity
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

    static func defaultExpandedSection(from nonEmptySections: Set<WorkSection>) -> WorkSection? {
        [.active, .queued, .recent].first { nonEmptySections.contains($0) }
    }
}

enum CodexCardPrimaryActionPolicy {
    static func opensThreadWhenPromptIsEmpty(status: WorkItemStatus) -> Bool {
        status == .waiting
    }
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
final class DesktopStatusPanelController: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    private static let userPanelWidthDefaultsKey = "desktopPanelUserWidth"
    private static let userPanelHeightDefaultsKey = "desktopPanelUserHeight"
    var onItemSelected: ((WorkItem) -> Void)?
    var onItemDetailsSelected: ((WorkItem) -> Void)?
    var onItemOutputSelected: ((WorkItem) -> Void)?
    var onItemAcknowledged: ((WorkItem) -> Void)?
    var onAllWaitingAcknowledged: (() -> Void)?
    var onCodexTransferSelected: ((WorkItem) -> Void)?
    var onCodexPromptSubmitted: ((String, CodexPrompt) -> Void)?
    var onNewConversationSubmitted: ((CodexPrompt) -> Void)?
    var onNewConversationDirectorySelected: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?

    private let panel: NSPanel
    private let floatingPanel: NSPanel
    private let floatingButtonView = FloatingStatusButtonView()
    private let titleLabel = NSTextField(labelWithString: "AI 工作岛")
    private let statusCapsule = StatusCapsuleView()
    private let newTaskInputBackground = RoundedInputBackground()
    private let newTaskPromptField = PastedImageTextField(string: "")
    private let newTaskImageCountLabel = NSTextField(labelWithString: "")
    private let newTaskSendButton = FirstMouseButton()
    private let newTaskDirectoryButton = FirstMouseButton()
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
    private var autoCollapseRequestID: UInt = 0
    private var hoverReconciliationTimer: Timer?
    private var completionRevealUntil: Date?
    private var codexResults: [String: String] = [:]
    private var codexRows: [String: WorkItemRowView] = [:]
    private var displayMode: DesktopPanelMode = .background
    private var contentMode: DesktopContentMode = .clean
    private var isSynchronizingWindowPositions = false
    private var isAutomaticallySizingPanel = false
    private var hasUserPreferredPanelSize = false
    private var isPanelBeingResized = false
    private let keepsPanelExpandedForUIReview = ProcessInfo.processInfo.arguments.contains(
        "--ui-review-panel"
    )

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesktopPanelLayout.width, height: 180),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
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
    var isWaitingForPointerLeaveToCollapse: Bool { isHoverExpanded }

    func setDisplayMode(_ mode: DesktopPanelMode) {
        displayMode = mode
        applyDisplayMode(hoverExpanded: isHoverExpanded && !isMinimizedToFloatingButton)
    }

    func setContentMode(_ mode: DesktopContentMode) {
        guard contentMode != mode else { return }
        contentMode = mode
        displayedItemIDs = nil
        displayedContentSignature = nil
        if let latestSnapshot { update(snapshot: latestSnapshot) }
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
        stopHoverReconciliation()
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        applyDisplayMode(hoverExpanded: false)
        if floatingPanel.isVisible {
            alignPanelToFloatingPanel()
        }
        floatingPanel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    /// Restores the panel through the same leave-to-collapse lifecycle used by
    /// the floating capsule. Explicitly reopening the app or enabling the panel
    /// must not leave it permanently expanded.
    func showAutoCollapsing() {
        show()
        isHoverExpanded = true
        refreshPanelHoverState()
        startHoverReconciliationIfNeeded()
        scheduleAutoCollapseIfNeeded()
    }

    func showCollapsed() {
        cancelPendingAutoCollapse()
        stopHoverReconciliation()
        isHoverExpanded = false
        isMinimizedToFloatingButton = true
        applyDisplayMode(hoverExpanded: false)
        positionFloatingPanelForCollapsedState()
        panel.orderOut(nil)
        floatingPanel.alphaValue = 1
        floatingPanel.orderFrontRegardless()
    }

    func hide() {
        cancelPendingAutoCollapse()
        stopHoverReconciliation()
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        applyDisplayMode(hoverExpanded: false)
        panel.orderOut(nil)
        floatingPanel.orderOut(nil)
    }

    func update(snapshot: WorkStatusSnapshot) {
        let newlyCompletedItemIDs = DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
            previous: latestSnapshot,
            current: snapshot
        )
        latestSnapshot = snapshot
        floatingButtonView.update(snapshot: snapshot)
        revealCompletedItemsIfNeeded(newlyCompletedItemIDs)
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

    func updateRecordingGuardian(_ state: VoiceMemoGuardianState?) {
        floatingButtonView.updateRecordingGuardian(state)
    }

    func updateRecordingWaveformLevel(_ level: Double) {
        floatingButtonView.updateRecordingWaveformLevel(level)
    }

    func setNewConversationBusy(_ isBusy: Bool) {
        newTaskPromptField.isEnabled = !isBusy
        newTaskSendButton.isEnabled = !isBusy
        newTaskDirectoryButton.isEnabled = !isBusy
        newTaskSendButton.toolTip = isBusy ? "正在创建新任务" : "创建新任务"
    }

    func updateCodexCardResults(from groups: [ProjectGroup]) {
        codexResults = Dictionary(uniqueKeysWithValues: groups.flatMap { group in
            group.threads.compactMap { thread in
                thread.lastAssistantResult.map { ("codex:\(thread.id)", $0) }
            }
        })
    }

    func removeViewedCodexItems(threadIDs: Set<String>) {
        guard let snapshot = latestSnapshot else { return }
        let itemIDs = Set(threadIDs.map { "codex:\($0)" })
        update(snapshot: WorkStatusSnapshot(
            items: snapshot.items.filter { !itemIDs.contains($0.id) },
            automationIssues: snapshot.automationIssues,
            codexShortTermLimit: snapshot.codexShortTermLimit,
            codexWeeklyLimit: snapshot.codexWeeklyLimit,
            companyQuota: snapshot.companyQuota
        ))
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
            empty.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
        } else {
            for sectionLayout in layout.sections {
                let header = WorkSectionHeaderView(
                    title: sectionLayout.section.title,
                    count: sectionLayout.totalCount,
                    expanded: sectionLayout.isExpanded,
                    collapsible: !sectionLayout.section.isAlwaysExpanded,
                    actionTitle: sectionLayout.section == .needsUser
                        && sectionLayout.items.contains(where: { $0.status == .waiting })
                        ? "全部已阅"
                        : nil
                )
                header.onAction = sectionLayout.section == .needsUser
                    ? { [weak self] in self?.onAllWaitingAcknowledged?() }
                    : nil
                if !sectionLayout.section.isAlwaysExpanded {
                    header.onToggle = { [weak self] in
                        self?.toggle(section: sectionLayout.section)
                    }
                }
                itemStack.addArrangedSubview(header)
                header.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
                for item in sectionLayout.items {
                    let row = WorkItemRowView(
                        item: item,
                        lastAssistantResult: codexResults[item.id],
                        contentMode: contentMode
                    )
                    row.onSelected = { [weak self] in self?.onItemSelected?(item) }
                    row.onDetailsSelected = { [weak self] in self?.onItemDetailsSelected?(item) }
                    row.onOutputSelected = item.outputPath == nil ? nil : { [weak self] in
                        self?.onItemOutputSelected?(item)
                    }
                    if item.id.hasPrefix("codex:"), item.status == .waiting {
                        row.onAcknowledgeSelected = { [weak self] in
                            self?.onItemAcknowledged?(item)
                        }
                    }
                    if item.id.hasPrefix("codex:") {
                        row.onCodexTransferSelected = { [weak self] in
                            self?.onCodexTransferSelected?(item)
                        }
                        row.onPromptSubmitted = { [weak self] prompt in
                            self?.onCodexPromptSubmitted?(item.id, prompt)
                        }
                        codexRows[item.id] = row
                    }
                    itemStack.addArrangedSubview(row)
                    row.widthAnchor.constraint(equalTo: itemStack.widthAnchor).isActive = true
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
            let fittedContentSize = DesktopPanelResizePolicy.automaticallyFittedContentSize(
                DesktopPanelLayout.contentSize(
                    visibleItemCount: layout.rowCount,
                    sectionCount: layout.sections.count,
                    conversationItemCount: layout.sections
                        .flatMap(\.items)
                        .filter { $0.id.hasPrefix("codex:") }
                        .count,
                    contentMode: contentMode
                ),
                currentContentSize: panel.contentView?.bounds.size ?? panel.contentLayoutRect.size,
                hasUserPreferredSize: hasUserPreferredPanelSize
            )
            isAutomaticallySizingPanel = true
            panel.setContentSize(fittedContentSize)
            isAutomaticallySizingPanel = false
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
                    .count,
                contentMode: contentMode
            )
            let fittedContentSize = DesktopPanelResizePolicy.automaticallyFittedContentSize(
                contentSize,
                currentContentSize: panel.contentView?.bounds.size ?? panel.contentLayoutRect.size,
                hasUserPreferredSize: hasUserPreferredPanelSize
            )
            let outerSize = panel.frameRect(
                forContentRect: NSRect(origin: .zero, size: fittedContentSize)
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
                isAutomaticallySizingPanel = true
                panel.animator().setFrame(targetFrame, display: true)
                itemStack.animator().alphaValue = 1
            } completionHandler: { [weak self] in
                guard let self else { return }
                isAutomaticallySizingPanel = false
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
            companyQuotaView.update(
                title: "公司额度",
                value: "待配置 · Edge 登录",
                remainingPercent: nil
            )
            companyQuotaView.isHidden = false
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
            let nonEmptySections = Set(grouped.keys)
            if let first = WorkSection.defaultExpandedSection(from: nonEmptySections) {
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
        stopHoverReconciliation()
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        floatingPanel.orderOut(nil)
        onVisibilityChanged?(false)
    }

    func windowDidMove(_ notification: Notification) {
        guard !isSynchronizingWindowPositions,
              let window = notification.object as? NSWindow,
              let screen = screenMostCovered(by: window.frame) else { return }
        let contentInsets: NSEdgeInsets = window === floatingPanel
            ? NSEdgeInsets(
                top: DesktopFloatingButtonLayout.animationInset,
                left: DesktopFloatingButtonLayout.animationInset,
                bottom: DesktopFloatingButtonLayout.animationInset,
                right: DesktopFloatingButtonLayout.animationInset
            )
            : DesktopWindowEdgeSnap.noInsets
        let snappedFrame = DesktopWindowEdgeSnap.snappedFrame(
            window.frame,
            in: screen.visibleFrame,
            contentInsets: contentInsets
        )
        if snappedFrame.origin != window.frame.origin {
            window.setFrameOrigin(snappedFrame.origin)
        }
        if window === panel {
            alignFloatingPanelToPanel()
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isSynchronizingWindowPositions,
              notification.object as? NSWindow === panel else { return }
        alignFloatingPanelToPanel()
        guard panel.isVisible, !isAutomaticallySizingPanel else { return }
        hasUserPreferredPanelSize = true
        if !panel.inLiveResize {
            persistUserPreferredPanelSize()
        }
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        isPanelBeingResized = true
        cancelPendingAutoCollapse()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === panel else { return }
        isPanelBeingResized = false
        let size = DesktopPanelResizePolicy.clampedFrameSize(panel.frame.size)
        if panel.frame.size != size {
            var frame = panel.frame
            frame.size = size
            frame.origin.y = panel.frame.maxY - size.height
            panel.setFrame(frame, display: true)
        }
        hasUserPreferredPanelSize = true
        persistUserPreferredPanelSize()
        alignFloatingPanelToPanel()
        refreshPanelHoverState()
        scheduleAutoCollapseIfNeeded()
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
        panel.minSize = DesktopPanelResizePolicy.minimumFrameSize
        panel.maxSize = DesktopPanelResizePolicy.maximumFrameSize
        panel.contentMinSize = DesktopPanelResizePolicy.minimumFrameSize
        panel.contentMaxSize = DesktopPanelResizePolicy.maximumFrameSize
        panel.resizeIncrements = NSSize(width: 1, height: 1)
        panel.setFrameAutosaveName("AIWorkStatusPanelFrame")
        restoreUserPreferredPanelSize()

        let materialView = PanelBackgroundView()
        materialView.appearance = NSAppearance(named: .darkAqua)
        materialView.autoresizingMask = [.width, .height]
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

        let header = NSStackView(views: [titleLabel, NSView(), statusCapsule])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        newTaskPromptField.placeholderString = "输入新任务…"
        newTaskPromptField.font = .systemFont(ofSize: 12)
        newTaskPromptField.isBordered = false
        newTaskPromptField.drawsBackground = false
        newTaskPromptField.focusRingType = .none
        newTaskPromptField.delegate = self
        newTaskPromptField.target = self
        newTaskPromptField.action = #selector(submitNewConversation)
        newTaskPromptField.setAccessibilityLabel("新任务指令")
        newTaskPromptField.onImagesChanged = { [weak self] count in
            self?.updateImageCountLabel(self?.newTaskImageCountLabel, count: count)
        }

        configureImageCountLabel(newTaskImageCountLabel)

        newTaskSendButton.image = NSImage(
            systemSymbolName: "arrow.up.circle.fill",
            accessibilityDescription: "创建新任务"
        )
        newTaskSendButton.isBordered = false
        newTaskSendButton.contentTintColor = .controlAccentColor
        newTaskSendButton.target = self
        newTaskSendButton.action = #selector(submitNewConversation)
        newTaskSendButton.toolTip = "创建新任务"
        newTaskSendButton.setAccessibilityLabel("创建新任务")
        newTaskSendButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        newTaskSendButton.widthAnchor.constraint(equalToConstant: 24).isActive = true

        newTaskDirectoryButton.image = NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: "更改新任务工作目录"
        )
        newTaskDirectoryButton.isBordered = false
        newTaskDirectoryButton.contentTintColor = .secondaryLabelColor
        newTaskDirectoryButton.target = self
        newTaskDirectoryButton.action = #selector(selectNewConversationDirectory)
        newTaskDirectoryButton.toolTip = "更改新任务工作目录"
        newTaskDirectoryButton.setAccessibilityLabel("更改新任务工作目录")
        newTaskDirectoryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        newTaskDirectoryButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

        let newTaskControls = NSStackView(
            views: [newTaskDirectoryButton, newTaskPromptField, newTaskImageCountLabel, newTaskSendButton]
        )
        newTaskControls.orientation = .horizontal
        newTaskControls.alignment = .centerY
        newTaskControls.spacing = 5
        newTaskControls.translatesAutoresizingMaskIntoConstraints = false
        newTaskInputBackground.addSubview(newTaskControls)
        NSLayoutConstraint.activate([
            newTaskInputBackground.heightAnchor.constraint(equalToConstant: 32),
            newTaskControls.leadingAnchor.constraint(equalTo: newTaskInputBackground.leadingAnchor, constant: 8),
            newTaskControls.trailingAnchor.constraint(equalTo: newTaskInputBackground.trailingAnchor, constant: -6),
            newTaskControls.topAnchor.constraint(equalTo: newTaskInputBackground.topAnchor, constant: 2),
            newTaskControls.bottomAnchor.constraint(equalTo: newTaskInputBackground.bottomAnchor, constant: -2),
        ])

        quotaStack.setViews([companyQuotaView, codexQuotaView], in: .leading)
        quotaStack.orientation = .horizontal
        quotaStack.alignment = .centerY
        quotaStack.distribution = .fillEqually
        quotaStack.spacing = 8
        quotaStack.heightAnchor.constraint(equalToConstant: 34).isActive = true

        itemStack.orientation = .vertical
        itemStack.alignment = .width
        itemStack.spacing = 6
        itemStack.distribution = .fill

        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = NSColor.white.withAlphaComponent(0.58)
        footerLabel.lineBreakMode = .byTruncatingMiddle

        let contentStack = NSStackView(views: [header, newTaskInputBackground, quotaStack, itemStack, footerLabel])
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.spacing = 11
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        materialView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(
                equalTo: materialView.leadingAnchor,
                constant: DesktopPanelLayout.contentHorizontalInset
            ),
            contentStack.trailingAnchor.constraint(
                equalTo: materialView.trailingAnchor,
                constant: -DesktopPanelLayout.contentHorizontalInset
            ),
            itemStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            contentStack.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 30),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: materialView.bottomAnchor, constant: -12),
        ])
    }

    @objc private func submitNewConversation() {
        let prompt = newTaskPromptField.takePrompt()
        guard !prompt.isEmpty, newTaskPromptField.isEnabled else { return }
        newTaskPromptField.stringValue = ""
        updateImageCountLabel(newTaskImageCountLabel, count: 0)
        onNewConversationSubmitted?(prompt)
    }

    private func configureImageCountLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .controlAccentColor
        label.isHidden = true
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    private func updateImageCountLabel(_ label: NSTextField?, count: Int) {
        label?.stringValue = "图×\(count)"
        label?.isHidden = count == 0
    }

    @objc private func selectNewConversationDirectory() {
        onNewConversationDirectorySelected?()
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === newTaskPromptField else { return }
        newTaskInputBackground.setFocused(true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField === newTaskPromptField else { return }
        newTaskInputBackground.setFocused(false)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === newTaskPromptField else { return false }
        return newTaskPromptField.handleDeleteCommand(commandSelector)
    }

    @objc private func minimizeToFloatingButton() {
        guard !isMinimizedToFloatingButton else { return }
        cancelPendingAutoCollapse()
        stopHoverReconciliation()
        isHoverExpanded = false
        isMinimizedToFloatingButton = true
        positionFloatingPanelForCollapsedState()
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
        floatingPanel.delegate = self
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
            self?.activateFloatingButton(hoverExpanded: true)
        }
        floatingButtonView.onHoverEntered = { [weak self] in
            self?.activateFloatingButton(hoverExpanded: true)
        }
    }

    private func activateFloatingButton(hoverExpanded: Bool) {
        guard DesktopFloatingPanelTransition.shouldActivate(
            isMinimizedToFloatingButton: isMinimizedToFloatingButton,
            isFloatingPanelVisible: floatingPanel.isVisible
        ) else { return }
        alignPanelToFloatingPanel()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard !reduceMotion else {
            isMinimizedToFloatingButton = false
            isHoverExpanded = hoverExpanded
            applyDisplayMode(hoverExpanded: hoverExpanded)
            floatingPanel.orderOut(nil)
            panel.orderFrontRegardless()
            refreshPanelHoverState()
            startHoverReconciliationIfNeeded()
            return
        }

        isMinimizedToFloatingButton = false
        isHoverExpanded = hoverExpanded
        applyDisplayMode(hoverExpanded: hoverExpanded)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        refreshPanelHoverState()
        startHoverReconciliationIfNeeded()
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

    private func revealCompletedItemsIfNeeded(_ itemIDs: Set<String>) {
        guard !itemIDs.isEmpty, isMinimizedToFloatingButton else { return }
        completionRevealUntil = Date().addingTimeInterval(
            DesktopCompletionReminderBehavior.revealDuration
        )
        activateFloatingButton(hoverExpanded: true)
        scheduleAutoCollapseIfNeeded()
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

    private func startHoverReconciliationIfNeeded() {
        guard isHoverExpanded, hoverReconciliationTimer == nil else { return }
        let timer = Timer(timeInterval: DesktopFloatingHoverBehavior.hoverReconciliationInterval,
                          repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isHoverExpanded, !self.isMinimizedToFloatingButton else {
                    self.stopHoverReconciliation()
                    return
                }
                self.refreshPanelHoverState()
            }
        }
        hoverReconciliationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHoverReconciliation() {
        hoverReconciliationTimer?.invalidate()
        hoverReconciliationTimer = nil
    }

    private func scheduleAutoCollapseIfNeeded() {
        guard !keepsPanelExpandedForUIReview else { return }
        guard !isPanelBeingResized else { return }
        guard DesktopFloatingHoverBehavior.shouldScheduleAutoCollapse(
            isHoverExpanded: isHoverExpanded,
            isPanelHovered: isPanelHovered,
            hasPendingAutoCollapse: pendingAutoCollapse != nil
        ) else { return }
        autoCollapseRequestID &+= 1
        let requestID = autoCollapseRequestID
        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  DesktopFloatingHoverBehavior.isCurrentAutoCollapseRequest(
                    firedRequestID: requestID,
                    currentRequestID: self.autoCollapseRequestID
                  ) else { return }
            // Clear before evaluating the state. If the delayed check loses a
            // race with AppKit hover/focus updates, reconciliation can queue a
            // fresh request instead of leaving the panel permanently open.
            self.pendingAutoCollapse = nil
            guard !self.isPanelBeingResized,
                  DesktopFloatingHoverBehavior.shouldAutoCollapse(
                    isHoverExpanded: self.isHoverExpanded,
                    isPanelHovered: self.isPanelHovered
                  ) else { return }
            minimizeToFloatingButton()
        }
        pendingAutoCollapse = workItem
        let completionRevealRemaining = completionRevealUntil.map {
            max(0, $0.timeIntervalSinceNow)
        } ?? 0
        let delay = DesktopCompletionReminderBehavior.autoCollapseDelay(
            standardDelay: DesktopFloatingHoverBehavior.collapseDelay,
            completionRevealRemaining: completionRevealRemaining
        )
        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    private func cancelPendingAutoCollapse() {
        autoCollapseRequestID &+= 1
        pendingAutoCollapse?.cancel()
        pendingAutoCollapse = nil
    }

    private func restoreUserPreferredPanelSize() {
        let defaults = UserDefaults.standard
        let width = defaults.double(forKey: Self.userPanelWidthDefaultsKey)
        let height = defaults.double(forKey: Self.userPanelHeightDefaultsKey)
        guard width > 0, height > 0 else { return }
        let size = DesktopPanelResizePolicy.clampedFrameSize(
            NSSize(width: width, height: height)
        )
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: false)
        hasUserPreferredPanelSize = true
    }

    private func persistUserPreferredPanelSize() {
        let size = DesktopPanelResizePolicy.clampedFrameSize(panel.frame.size)
        UserDefaults.standard.set(size.width, forKey: Self.userPanelWidthDefaultsKey)
        UserDefaults.standard.set(size.height, forKey: Self.userPanelHeightDefaultsKey)
    }

    private func positionFloatingPanelForCollapsedState() {
        guard !didPositionFloatingPanel else {
            alignFloatingPanelToPanel()
            return
        }
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
        if let screen = screenMostCovered(by: floatingPanel.frame) {
            let inset = DesktopFloatingButtonLayout.animationInset
            let visibleFrame = DesktopWindowVisibility.clampedFrame(
                floatingPanel.frame,
                in: screen.visibleFrame,
                contentInsets: NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
            )
            floatingPanel.setFrameOrigin(visibleFrame.origin)
        }
        didPositionFloatingPanel = true
        alignPanelToFloatingPanel()
    }

    private func alignPanelToFloatingPanel() {
        setFrame(
            DesktopPanelAnchorLayout.panelFrame(
                anchoredToFloatingPanel: floatingPanel.frame,
                panelSize: panel.frame.size
            ),
            for: panel
        )
    }

    private func alignFloatingPanelToPanel() {
        setFrame(
            DesktopPanelAnchorLayout.floatingFrame(
                anchoredToPanel: panel.frame,
                floatingSize: DesktopFloatingButtonLayout.canvasSize
            ),
            for: floatingPanel
        )
    }

    private func setFrame(_ frame: NSRect, for window: NSWindow) {
        guard window.frame != frame else { return }
        isSynchronizingWindowPositions = true
        window.setFrame(frame, display: false)
        isSynchronizingWindowPositions = false
    }

    private func screenMostCovered(by frame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            let lhsIntersection = lhs.visibleFrame.intersection(frame)
            let rhsIntersection = rhs.visibleFrame.intersection(frame)
            let lhsArea = lhsIntersection.isNull ? 0 : lhsIntersection.width * lhsIntersection.height
            let rhsArea = rhsIntersection.isNull ? 0 : rhsIntersection.width * rhsIntersection.height
            return lhsArea < rhsArea
        } ?? NSScreen.main
    }
}

@MainActor
final class RecordingWaveformView: NSView {
    private static let barCount = 7
    private static let profile: [CGFloat] = [0.52, 0.78, 0.64, 1.0, 0.70, 0.86, 0.56]
    private let bars = (0..<barCount).map { _ in CALayer() }
    private var level: CGFloat = 0
    private var tintColor = NSColor.systemRed

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        bars.forEach {
            $0.cornerRadius = 0.8
            layer?.addSublayer($0)
        }
        update(level: 0, tintColor: .systemRed)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        applyBarFrames(animated: false)
    }

    func update(level: Double, tintColor: NSColor) {
        self.level = CGFloat(min(max(level, 0), 1))
        self.tintColor = tintColor
        applyBarFrames(animated: true)
    }

    func heightsForTesting() -> [CGFloat] {
        bars.map(\.frame.height)
    }

    private func applyBarFrames(animated: Bool) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let spacing: CGFloat = 1.1
        let barWidth = max(1.2, (bounds.width - spacing * CGFloat(Self.barCount - 1)) / CGFloat(Self.barCount))
        let usableHeight = max(2, bounds.height - 3)
        let baseLevel = max(0.10, level)
        CATransaction.begin()
        CATransaction.setAnimationDuration(
            animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.09 : 0
        )
        for (index, bar) in bars.enumerated() {
            let shaped = min(1, baseLevel * (0.62 + Self.profile[index] * 0.62))
            let height = max(2, usableHeight * shaped)
            bar.backgroundColor = tintColor.withAlphaComponent(0.92).cgColor
            bar.frame = CGRect(
                x: CGFloat(index) * (barWidth + spacing),
                y: bounds.midY - height / 2,
                width: barWidth,
                height: height
            )
        }
        CATransaction.commit()
    }
}

@MainActor
final class FloatingStatusButtonView: NSVisualEffectView {
    var onActivate: (() -> Void)?
    var onHoverEntered: (() -> Void)?

    private let statusDot = NSView()
    private let statusHalo = NSView()
    private let recordingWaveform = RecordingWaveformView()
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
    private var carouselPresentations: [DesktopFloatingButtonPresentation] = []
    private var carouselIndex = 0
    private var carouselTimer: Timer?
    private var recordingGuardianState: VoiceMemoGuardianState?
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

        recordingWaveform.translatesAutoresizingMaskIntoConstraints = false
        recordingWaveform.isHidden = true
        statusHalo.addSubview(recordingWaveform)

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
            recordingWaveform.leadingAnchor.constraint(equalTo: statusHalo.leadingAnchor, constant: 1),
            recordingWaveform.trailingAnchor.constraint(equalTo: statusHalo.trailingAnchor, constant: -1),
            recordingWaveform.topAnchor.constraint(equalTo: statusHalo.topAnchor, constant: 1),
            recordingWaveform.bottomAnchor.constraint(equalTo: statusHalo.bottomAnchor, constant: -1),
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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            carouselTimer?.invalidate()
            carouselTimer = nil
        } else if carouselTimer == nil {
            let timer = Timer(
                timeInterval: DesktopFloatingButtonMotion.carouselInterval,
                target: self,
                selector: #selector(advanceCarousel),
                userInfo: nil,
                repeats: true
            )
            RunLoop.main.add(timer, forMode: .common)
            carouselTimer = timer
        }
    }

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
        let nextPresentations = DesktopFloatingButtonPresentation.carousel(for: snapshot)
        if let currentPresentation,
           let retainedIndex = nextPresentations.firstIndex(of: currentPresentation) {
            carouselIndex = retainedIndex
        } else {
            carouselIndex = 0
        }
        carouselPresentations = nextPresentations
        guard recordingGuardianState == nil else { return }
        apply(nextPresentations[carouselIndex], isCarouselAdvance: false)
    }

    func updateRecordingGuardian(_ state: VoiceMemoGuardianState?) {
        recordingGuardianState = state
        if let state {
            statusDot.isHidden = true
            recordingWaveform.isHidden = false
            recordingWaveform.update(
                level: state.phase == .silence ? 0 : 0.12,
                tintColor: state.phase == .silence ? .systemOrange : .systemRed
            )
            apply(.recordingGuardian(state), isCarouselAdvance: false)
        } else if !carouselPresentations.isEmpty {
            recordingWaveform.update(level: 0, tintColor: .systemRed)
            recordingWaveform.isHidden = true
            statusDot.isHidden = false
            carouselIndex = min(carouselIndex, carouselPresentations.count - 1)
            apply(carouselPresentations[carouselIndex], isCarouselAdvance: false)
        }
    }

    func updateRecordingWaveformLevel(_ level: Double) {
        guard let recordingGuardianState else { return }
        recordingWaveform.update(
            level: recordingGuardianState.phase == .silence ? 0 : level,
            tintColor: recordingGuardianState.phase == .silence ? .systemOrange : .systemRed
        )
    }

    func recordingWaveformHeightsForTesting() -> [CGFloat] {
        recordingWaveform.layoutSubtreeIfNeeded()
        return recordingWaveform.heightsForTesting()
    }

    func isRecordingWaveformVisibleForTesting() -> Bool {
        !recordingWaveform.isHidden && statusDot.isHidden
    }

    private func update(items: [WorkItem], latestCompleted: WorkItem?) {
        let presentation = DesktopFloatingButtonPresentation.make(
            items: items,
            latestCompleted: latestCompleted
        )
        carouselPresentations = [presentation]
        carouselIndex = 0
        apply(presentation, isCarouselAdvance: false)
    }

    @objc func advanceCarousel() {
        if let recordingGuardianState {
            apply(.recordingGuardian(recordingGuardianState), isCarouselAdvance: false)
            return
        }
        guard carouselPresentations.count > 1 else { return }
        carouselIndex = (carouselIndex + 1) % carouselPresentations.count
        apply(carouselPresentations[carouselIndex], isCarouselAdvance: true)
    }

    func displayedTextForTesting() -> String {
        statusLabel.stringValue
    }

    private func apply(
        _ presentation: DesktopFloatingButtonPresentation,
        isCarouselAdvance: Bool
    ) {
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
        if shouldAnimate && !isCarouselAdvance {
            animateStatusTransition(tintColor: presentation.tintColor)
        }
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
        if !didDrag { handleActivate() }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        didDrag = false
    }

    override func accessibilityPerformPress() -> Bool {
        handleActivate()
        return true
    }

    func handleActivate() {
        onActivate?()
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
    var onAction: (() -> Void)?

    init(
        title: String,
        count: Int,
        expanded: Bool,
        collapsible: Bool = true,
        actionTitle: String? = nil
    ) {
        super.init(frame: .zero)
        let button = FirstMouseButton(
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
        var views: [NSView] = [button, NSView(), countLabel]
        if let actionTitle {
            let actionButton = FirstMouseButton(
                title: actionTitle,
                target: self,
                action: #selector(runAction)
            )
            actionButton.isBordered = false
            actionButton.font = .systemFont(ofSize: 9, weight: .medium)
            actionButton.contentTintColor = .controlAccentColor
            actionButton.toolTip = "将所有已完成的 Codex 结果标记为已阅"
            views.append(actionButton)
        }
        let row = NSStackView(views: views)
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
    @objc private func runAction() { onAction?() }
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
private final class WorkItemRowView: NSView, NSTextFieldDelegate {
    var onSelected: (() -> Void)?
    var onDetailsSelected: (() -> Void)?
    var onPromptSubmitted: ((CodexPrompt) -> Void)?
    var onCodexTransferSelected: (() -> Void)? {
        didSet { codexTransferButton.isHidden = onCodexTransferSelected == nil }
    }
    var onAcknowledgeSelected: (() -> Void)? {
        didSet { acknowledgeButton.isHidden = onAcknowledgeSelected == nil }
    }
    var onOutputSelected: (() -> Void)? {
        didSet { outputButton.isHidden = onOutputSelected == nil }
    }

    private let actions = NSStackView()
    private let outputButton = FirstMouseButton()
    private let codexTransferButton = FirstMouseButton()
    private let acknowledgeButton = FirstMouseButton()
    private let conversationInputBackground = RoundedInputBackground()
    private let promptField = PastedImageTextField(string: "")
    private let imageCountLabel = NSTextField(labelWithString: "")
    private let sendButton = FirstMouseButton()
    private let conversationStatusLabel = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var isHovering = false
    private let opensThreadWhenPromptIsEmpty: Bool
    private let contentMode: DesktopContentMode

    init(
        item: WorkItem,
        lastAssistantResult: String? = nil,
        contentMode: DesktopContentMode = .clean
    ) {
        self.contentMode = contentMode
        opensThreadWhenPromptIsEmpty = CodexCardPrimaryActionPolicy
            .opensThreadWhenPromptIsEmpty(status: item.status)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        layer?.borderColor = DesktopPanelPalette.stroke.withAlphaComponent(0.88).cgColor
        layer?.backgroundColor = DesktopPanelPalette.card.withAlphaComponent(0.98).cgColor
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
        title.font = .systemFont(ofSize: 13.5, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = 1
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let detailText = contentMode == .detailed
            ? item.displayDetail
            : item.phase.map { "正在：\($0) · \(item.displayDetail)" } ?? item.displayDetail
        let detail = NSTextField(labelWithString: detailText)
        detail.font = .systemFont(ofSize: 11.5)
        detail.textColor = NSColor.white.withAlphaComponent(0.68)
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
        status.font = .systemFont(ofSize: 10.5, weight: .semibold)
        status.textColor = contentMode == .detailed ? .labelColor : item.status.color
        status.alignment = .right
        status.setContentCompressionResistancePriority(.required, for: .horizontal)

        // The card is visually one click target, but AppKit label/stack views
        // consume mouse events instead of bubbling them to WorkItemRowView.
        // Route every non-interactive part through the same selection action.
        [indicator, textStack, status].forEach {
            $0.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(selectRow)))
        }

        outputButton.image = NSImage(systemSymbolName: "doc", accessibilityDescription: "打开产出")
        outputButton.isBordered = false
        outputButton.toolTip = "打开产出"
        outputButton.target = self
        outputButton.action = #selector(openOutput)
        codexTransferButton.image = NSImage(
            systemSymbolName: "arrow.up.forward.app",
            accessibilityDescription: "转到 Codex"
        )
        codexTransferButton.isBordered = false
        codexTransferButton.toolTip = item.status == .waiting
            ? "查看结果并继续处理"
            : "停止工作岛占用并转到 Codex"
        codexTransferButton.target = self
        codexTransferButton.action = #selector(transferToCodex)
        codexTransferButton.isHidden = true
        acknowledgeButton.image = NSImage(
            systemSymbolName: "checkmark.circle",
            accessibilityDescription: "标记已阅"
        )
        acknowledgeButton.isBordered = false
        acknowledgeButton.toolTip = "标记已阅"
        acknowledgeButton.target = self
        acknowledgeButton.action = #selector(acknowledge)
        acknowledgeButton.isHidden = true
        let detailsButton = actionButton(symbol: "info.circle", toolTip: "查看详情")
        detailsButton.target = self
        detailsButton.action = #selector(showDetails)
        actions.setViews(
            [codexTransferButton, acknowledgeButton, outputButton, detailsButton],
            in: .leading
        )
        actions.orientation = .horizontal
        actions.spacing = 3
        actions.alphaValue = 0
        actions.isHidden = true
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        let mainRow = NSStackView(views: [indicator, textStack, NSView(), status, actions])
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 8
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        if item.id.hasPrefix("codex:") {
            let summary: CodexCardStatusSummary
            if item.status == .running {
                summary = .running(
                    phase: item.phase,
                    completedSteps: item.phaseIndex,
                    totalSteps: item.phaseCount,
                    recentActivity: item.recentActivity
                )
            } else {
                summary = .waiting(lastAssistantResult: lastAssistantResult)
            }
            let conversationStatusText = contentMode == .detailed ? summary.detailedText : summary.text
            conversationStatusLabel.stringValue = conversationStatusText
            conversationStatusLabel.font = .systemFont(
                ofSize: contentMode.conversationStatusFontSize,
                weight: contentMode == .detailed ? .medium : .regular
            )
            conversationStatusLabel.textColor = contentMode == .detailed
                ? NSColor.white.withAlphaComponent(0.90)
                : NSColor.white.withAlphaComponent(0.76)
            conversationStatusLabel.lineBreakMode = .byTruncatingTail
            conversationStatusLabel.maximumNumberOfLines = contentMode.conversationStatusLineCount
            conversationStatusLabel.cell?.wraps = true
            conversationStatusLabel.toolTip = conversationStatusText
            conversationStatusLabel.setContentCompressionResistancePriority(
                .defaultLow,
                for: .horizontal
            )
            conversationStatusLabel.addGestureRecognizer(
                NSClickGestureRecognizer(target: self, action: #selector(selectRow))
            )

            promptField.placeholderString = "继续该项目…"
            promptField.font = .systemFont(ofSize: 12)
            promptField.isBordered = false
            promptField.drawsBackground = false
            promptField.focusRingType = .none
            promptField.delegate = self
            promptField.target = self
            promptField.action = #selector(submitPrompt)
            promptField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            imageCountLabel.font = .systemFont(ofSize: 10, weight: .medium)
            imageCountLabel.textColor = .controlAccentColor
            imageCountLabel.isHidden = true
            imageCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            promptField.onImagesChanged = { [weak self] count in
                self?.imageCountLabel.stringValue = "图×\(count)"
                self?.imageCountLabel.isHidden = count == 0
            }

            sendButton.image = NSImage(
                systemSymbolName: "arrow.up.circle.fill",
                accessibilityDescription: "继续该项目"
            )
            sendButton.isBordered = false
            sendButton.contentTintColor = .controlAccentColor
            sendButton.target = self
            sendButton.action = #selector(submitPrompt)
            sendButton.toolTip = opensThreadWhenPromptIsEmpty
                ? "打开 Codex；输入内容后发送"
                : "继续该项目"

            let inputControls = NSStackView(views: [promptField, imageCountLabel, sendButton])
            inputControls.orientation = .horizontal
            inputControls.alignment = .centerY
            inputControls.spacing = 5
            inputControls.translatesAutoresizingMaskIntoConstraints = false
            conversationInputBackground.addSubview(inputControls)
            NSLayoutConstraint.activate([
                conversationInputBackground.heightAnchor.constraint(equalToConstant: 27),
                inputControls.leadingAnchor.constraint(
                    equalTo: conversationInputBackground.leadingAnchor,
                    constant: 7
                ),
                inputControls.trailingAnchor.constraint(
                    equalTo: conversationInputBackground.trailingAnchor,
                    constant: -5
                ),
                inputControls.topAnchor.constraint(equalTo: conversationInputBackground.topAnchor, constant: 1),
                inputControls.bottomAnchor.constraint(equalTo: conversationInputBackground.bottomAnchor, constant: -1),
            ])
            sendButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

            var conversationViews: [NSView] = [mainRow, conversationStatusLabel]
            if let count = item.phaseCount, count > 0 {
                let progress = StageProgressView(
                    count: count,
                    current: min(max(item.phaseIndex ?? 0, 0), count),
                    color: item.status.color
                )
                progress.heightAnchor.constraint(equalToConstant: 3).isActive = true
                conversationViews.append(progress)
            }
            conversationViews.append(conversationInputBackground)
            let stack = NSStackView(views: conversationViews)
            stack.orientation = .vertical
            stack.alignment = .width
            stack.spacing = 4
            stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                heightAnchor.constraint(equalToConstant: contentMode.conversationCardHeight),
                stack.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: DesktopPanelLayout.workItemHorizontalInset
                ),
                stack.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -DesktopPanelLayout.workItemHorizontalInset
                ),
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

        if !item.id.hasPrefix("codex:"), let count = item.phaseCount, count > 0 {
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
    override func mouseUp(with event: NSEvent) { selectRow() }

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
        conversationStatusLabel.textColor = contentMode == .detailed
            ? NSColor.white.withAlphaComponent(isBusy ? 0.94 : 0.82)
            : (isBusy ? .controlAccentColor : .secondaryLabelColor)
        promptField.isEnabled = !isBusy
        sendButton.isEnabled = !isBusy
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        conversationInputBackground.setFocused(true)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        conversationInputBackground.setFocused(false)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === promptField else { return false }
        return promptField.handleDeleteCommand(commandSelector)
    }

    private func setHovering(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            actions.isHidden = false
            actions.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            actions.animator().alphaValue = hovering ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, !isHovering else { return }
            actions.isHidden = true
        }
        layer?.borderColor = (hovering ? NSColor.controlAccentColor : DesktopPanelPalette.stroke)
            .withAlphaComponent(hovering ? 0.50 : 0.88).cgColor
        layer?.backgroundColor = DesktopPanelPalette.card
            .blended(withFraction: hovering ? 0.055 : 0, of: .white)?
            .withAlphaComponent(0.98).cgColor
    }

    private func actionButton(symbol: String, toolTip: String) -> NSButton {
        let button = FirstMouseButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.isBordered = false
        button.toolTip = toolTip
        return button
    }

    @objc private func openOutput() { onOutputSelected?() }
    @objc private func selectRow() { onSelected?() }
    @objc private func transferToCodex() { onCodexTransferSelected?() }
    @objc private func acknowledge() { onAcknowledgeSelected?() }
    @objc private func showDetails() { onDetailsSelected?() }
    @objc private func submitPrompt() {
        let prompt = promptField.takePrompt()
        guard promptField.isEnabled else { return }
        if prompt.isEmpty, opensThreadWhenPromptIsEmpty {
            onCodexTransferSelected?()
            return
        }
        guard !prompt.isEmpty else { return }
        promptField.stringValue = ""
        imageCountLabel.isHidden = true
        onPromptSubmitted?(prompt)
    }
}

@MainActor
final class PastedImageTextField: NSTextField {
    var onImagesChanged: ((Int) -> Void)?
    private var imageURLs: [URL] = []
    var pastedImageCount: Int { imageURLs.count }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func handleDeleteCommand(_ commandSelector: Selector) -> Bool {
        guard stringValue.isEmpty,
              commandSelector == #selector(NSResponder.deleteBackward(_:))
                || commandSelector == #selector(NSResponder.deleteForward(_:)),
              let url = imageURLs.popLast() else { return false }
        try? FileManager.default.removeItem(at: url)
        onImagesChanged?(imageURLs.count)
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPaste = modifiers == .command
            && event.charactersIgnoringModifiers?.lowercased() == "v"
        if isPaste, let image = NSImage(pasteboard: .general), let url = Self.writeTemporaryPNG(image) {
            imageURLs.append(url)
            onImagesChanged?(imageURLs.count)
            return true
        }
        let isDelete = modifiers.isEmpty && (event.keyCode == 51 || event.characters == "\u{7f}")
        if isDelete, stringValue.isEmpty, let url = imageURLs.popLast() {
            try? FileManager.default.removeItem(at: url)
            onImagesChanged?(imageURLs.count)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    func takePrompt() -> CodexPrompt {
        let prompt = CodexPrompt(
            text: stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURLs: imageURLs
        )
        imageURLs = []
        onImagesChanged?(0)
        return prompt
    }

    private static func writeTemporaryPNG(_ image: NSImage) -> URL? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AIWorkIsland-PastedImages", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSSound.beep()
            return nil
        }
    }
}

@MainActor
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class RoundedInputBackground: NSView {
    private let highlightLayer = CAGradientLayer()
    private var isFocused = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        highlightLayer.startPoint = CGPoint(x: 0, y: 0)
        highlightLayer.endPoint = CGPoint(x: 1, y: 1)
        layer?.addSublayer(highlightLayer)
        updateAppearance()
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        highlightLayer.frame = bounds
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func setFocused(_ focused: Bool) {
        guard isFocused != focused else { return }
        isFocused = focused
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            updateAppearance()
        }
    }

    private func updateAppearance() {
        let accent = NSColor.controlAccentColor
        highlightLayer.colors = [
            NSColor.white.withAlphaComponent(0.06).cgColor,
            accent.withAlphaComponent(isFocused ? 0.10 : 0.025).cgColor,
            NSColor.clear.cgColor,
        ]
        layer?.backgroundColor = DesktopPanelPalette.input.withAlphaComponent(0.99).cgColor
        layer?.borderWidth = isFocused ? 1.1 : 0.7
        layer?.borderColor = (isFocused ? accent : DesktopPanelPalette.stroke)
            .withAlphaComponent(isFocused ? 0.78 : 0.92).cgColor
        layer?.shadowColor = accent.withAlphaComponent(0.22).cgColor
        layer?.shadowOpacity = isFocused ? 1 : 0
        layer?.shadowRadius = 8
        layer?.shadowOffset = .zero
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
        material = .hudWindow
        blendingMode = .withinWindow
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    private func updateColors() {
        tintLayer.colors = [
            NSColor.white.withAlphaComponent(0.075).cgColor,
            NSColor.controlAccentColor.withAlphaComponent(0.045).cgColor,
            NSColor.black.withAlphaComponent(0.08).cgColor,
        ]
        highlightLayer.colors = [
            NSColor.white.withAlphaComponent(0.19).cgColor,
            NSColor.white.withAlphaComponent(0.055).cgColor,
            NSColor.clear.cgColor,
        ]
        layer?.backgroundColor = DesktopPanelPalette.base.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = 0.8
        layer?.borderColor = DesktopPanelPalette.stroke.withAlphaComponent(0.95).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.46).cgColor
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
