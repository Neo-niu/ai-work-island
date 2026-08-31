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
        case .clean: "精简 · 最近 4 条进度"
        case .detailed: "详细 · 最近 6 条进度"
        }
    }

    var maximumActivityCount: Int { self == .clean ? 4 : 6 }
    var conversationStatusFontSize: CGFloat { self == .clean ? 11 : 11.5 }

    func conversationStatusTextColor(isBusy: Bool) -> NSColor {
        switch self {
        case .detailed:
            .labelColor
        case .clean:
            isBusy ? .controlAccentColor : .secondaryLabelColor
        }
    }
}

enum DesktopConversationLayout {
    static let activityLineBreakMode: NSLineBreakMode = .byWordWrapping
    static let compactHeaderHeight: CGFloat = 32
    static let titleLineLimit = 1
    static let historicalActivityLineLimit = 1
    static let currentActivityLineLimit = 2
    static let completedResultLineLimit = 0
    static let maximumCompletedResultHeight: CGFloat = 360
    static let defaultMeasurementWidth = DesktopPanelLayout.conversationContentWidth
    static let completedResultToInputSpacing: CGFloat = 5
    static let completedInputHeight: CGFloat = 27
    static let completedVerticalInsets: CGFloat = 6
    static let completedHeaderToResultSpacing: CGFloat = 2
    static let runningVerticalInsets: CGFloat = 10
    static let runningHeaderToActivitySpacing: CGFloat = 4
    static let runningActivityToInputSpacing: CGFloat = 10
    static let runningActivityToProgressSpacing: CGFloat = 7
    static let runningProgressHeight: CGFloat = 13
    static let runningProgressToInputSpacing: CGFloat = 8
    static let completedResultMarkerTopInset: CGFloat = 0

    static func resolvedMeasurementWidth(
        itemStackWidth: CGFloat,
        panelContentWidth: CGFloat
    ) -> CGFloat {
        if panelContentWidth > DesktopPanelLayout.contentHorizontalInset * 2
            + DesktopPanelLayout.workItemHorizontalInset * 2 {
            return panelContentWidth
                - DesktopPanelLayout.contentHorizontalInset * 2
                - DesktopPanelLayout.workItemHorizontalInset * 2
        }
        if itemStackWidth > DesktopPanelLayout.workItemHorizontalInset * 2 {
            return itemStackWidth - DesktopPanelLayout.workItemHorizontalInset * 2
        }
        return defaultMeasurementWidth
    }

    static func cardHeight(
        item: WorkItem,
        lastAssistantResult: String?,
        contentMode: DesktopContentMode,
        measurementWidth: CGFloat = defaultMeasurementWidth
    ) -> CGFloat {
        // Automation rows have their own compact 56pt layout. Feeding them
        // through the Codex conversation height calculator adds a second,
        // incompatible height constraint when an automation completes.
        guard item.id.hasPrefix("codex:") else { return 56 }
        let summary = summary(
            item: item,
            lastAssistantResult: lastAssistantResult,
            contentMode: contentMode
        )
        let headerHeight = titleHeaderHeight(for: item.displayTitle, width: measurementWidth)
        if item.status == .running {
            let entries = Array(summary.entries.prefix(contentMode.maximumActivityCount))
            let visibleLineCount = max(1, entries.enumerated().reduce(into: 0) { total, pair in
                let maximum = pair.offset == entries.count - 1
                    ? currentActivityLineLimit
                    : historicalActivityLineLimit
                total += estimatedLineCount(for: pair.element, maximum: maximum)
            })
            let lineHeight = ceil(NSFont.systemFont(ofSize: 12.5).boundingRectForFont.height)
            let entrySpacing = CGFloat(max(0, entries.count - 1)) * 6
            let progressHeight: CGFloat
            if summary.progressText == nil {
                progressHeight = runningActivityToInputSpacing
            } else {
                progressHeight = runningActivityToProgressSpacing
                    + runningProgressHeight
                    + runningProgressToInputSpacing
            }
            return headerHeight
                + runningVerticalInsets
                + runningHeaderToActivitySpacing
                + CGFloat(visibleLineCount) * lineHeight
                + entrySpacing
                + progressHeight
                + completedInputHeight
        } else {
            let result = summary.entries.first ?? ""
            let resultHeight = min(
                measuredTextHeight(for: result, width: measurementWidth),
                maximumCompletedResultHeight
            )
            return headerHeight + resultHeight
                + completedHeaderToResultSpacing
                + completedResultToInputSpacing
                + completedInputHeight
                + completedVerticalInsets
        }
    }

    static func extraHeight(
        item: WorkItem,
        lastAssistantResult: String?,
        contentMode: DesktopContentMode,
        measurementWidth: CGFloat = defaultMeasurementWidth
    ) -> Int {
        max(0, Int(cardHeight(
            item: item,
            lastAssistantResult: lastAssistantResult,
            contentMode: contentMode,
            measurementWidth: measurementWidth
        ) - 62))
    }

    static func summary(
        item: WorkItem,
        lastAssistantResult: String?,
        contentMode: DesktopContentMode
    ) -> CodexCardStatusSummary {
        if item.status == .running {
            return .running(
                phase: item.phase,
                completedSteps: item.phaseIndex,
                totalSteps: item.phaseCount,
                recentActivity: item.recentActivity,
                activities: Array((item.activities ?? []).suffix(contentMode.maximumActivityCount))
            )
        }
        return .waiting(lastAssistantResult: lastAssistantResult)
    }

    private static func estimatedLineCount(for text: String, maximum: Int? = nil) -> Int {
        let font = NSFont.systemFont(ofSize: 12.5)
        let estimated = max(1, Int(ceil(
            measuredTextHeight(for: text) / font.boundingRectForFont.height
        )))
        return maximum.map { min(estimated, $0) } ?? estimated
    }

    static func measuredTextHeight(
        for text: String,
        width: CGFloat = defaultMeasurementWidth
    ) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12.5)
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return max(font.boundingRectForFont.height, ceil(measured.height))
    }

    static func titleHeaderHeight(for text: String, width: CGFloat) -> CGFloat {
        compactHeaderHeight
    }
}

@MainActor
enum DesktopResultTextRenderer {
    private static let bodyFont = NSFont.systemFont(ofSize: 12.5, weight: .regular)
    private static let headerFont = NSFont.systemFont(ofSize: 12.5, weight: .semibold)

    static func attributedString(for source: String) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let lines = source.components(separatedBy: .newlines)
        var index = 0

        while index < lines.count {
            if index + 1 < lines.count,
               let headers = tableCells(in: lines[index]),
               isSeparatorRow(lines[index + 1], columnCount: headers.count) {
                var rows = [headers]
                index += 2
                while index < lines.count,
                      let cells = tableCells(in: lines[index]),
                      cells.count == headers.count {
                    rows.append(cells)
                    index += 1
                }
                appendTable(rows, to: output)
                continue
            }

            output.append(NSAttributedString(
                string: lines[index],
                attributes: [.font: bodyFont, .foregroundColor: NSColor.labelColor]
            ))
            if index < lines.count - 1 { output.append(NSAttributedString(string: "\n")) }
            index += 1
        }
        return output
    }

    static func containsTable(in source: String) -> Bool {
        let lines = source.components(separatedBy: .newlines)
        return lines.indices.dropLast().contains { index in
            guard let headers = tableCells(in: lines[index]) else { return false }
            return isSeparatorRow(lines[index + 1], columnCount: headers.count)
        }
    }

    private static func tableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        let content = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        let cells = content.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return cells.count >= 2 ? cells : nil
    }

    private static func isSeparatorRow(_ line: String, columnCount: Int) -> Bool {
        guard let cells = tableCells(in: line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            let rule = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return rule.count >= 3 && rule.allSatisfy { $0 == "-" }
        }
    }

    private static func appendTable(_ rows: [[String]], to output: NSMutableAttributedString) {
        let table = NSTextTable()
        table.numberOfColumns = rows[0].count
        table.collapsesBorders = true
        table.hidesEmptyCells = false

        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, text) in row.enumerated() {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: columnIndex,
                    columnSpan: 1
                )
                block.setWidth(0.5, type: .absoluteValueType, for: .border)
                block.setBorderColor(.separatorColor)
                block.setWidth(5, type: .absoluteValueType, for: .padding)
                if rowIndex == 0 {
                    block.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08)
                }
                let paragraph = NSMutableParagraphStyle()
                paragraph.textBlocks = [block]
                paragraph.lineBreakMode = .byWordWrapping
                output.append(NSAttributedString(
                    string: text + "\n",
                    attributes: [
                        .font: rowIndex == 0 ? headerFont : bodyFont,
                        .foregroundColor: NSColor.labelColor,
                        .paragraphStyle: paragraph,
                    ]
                ))
            }
        }
    }
}

enum DesktopPanelHeaderLayout {
    static let minimumHeight: CGFloat = 24
}

enum DesktopPanelCenterLayout {
    static func centeredFrame(panelSize: NSSize, in visibleFrame: NSRect) -> NSRect {
        NSRect(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.midY - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
    }
}

enum DesktopPanelCapsuleTopAlignment {
    static func alignedFrame(
        _ panelFrame: NSRect,
        toFloatingFrame floatingFrame: NSRect,
        animationInset: CGFloat = DesktopFloatingButtonLayout.animationInset
    ) -> NSRect {
        var aligned = panelFrame
        aligned.origin.y = floatingFrame.maxY - animationInset - panelFrame.height
        return aligned
    }
}

enum DesktopPanelRememberedPosition {
    static func restoredFrame(
        panelSize: NSSize,
        center: NSPoint,
        visibleFrames: [NSRect],
        fallbackVisibleFrame: NSRect
    ) -> NSRect {
        let candidate = NSRect(
            x: center.x - panelSize.width / 2,
            y: center.y - panelSize.height / 2,
            width: panelSize.width,
            height: panelSize.height
        )
        let bestMatch = visibleFrames
            .map { visibleFrame -> (frame: NSRect, area: CGFloat) in
                let intersection = visibleFrame.intersection(candidate)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                return (visibleFrame, area)
            }
            .max { $0.area < $1.area }
        let targetVisibleFrame = bestMatch.flatMap { $0.area > 0 ? $0.frame : nil }
            ?? fallbackVisibleFrame
        return DesktopWindowVisibility.clampedFrame(candidate, in: targetVisibleFrame)
    }
}

enum DesktopPanelTransitionMotion {
    static let travel: CGFloat = 14
    static let expandTravel: CGFloat = 20
    static let collapseTravel: CGFloat = 12
    static let expandSourceScale: CGFloat = 0.94
    static let collapseSourceScale: CGFloat = 0.965

    static func frameTowardSource(
        targetFrame: NSRect,
        sourceFrame: NSRect,
        travel: CGFloat = travel,
        scale: CGFloat = 1
    ) -> NSRect {
        let delta = NSPoint(
            x: sourceFrame.midX - targetFrame.midX,
            y: sourceFrame.midY - targetFrame.midY
        )
        let length = hypot(delta.x, delta.y)
        let direction = length > 0
            ? NSPoint(x: delta.x / length, y: delta.y / length)
            : .zero
        let clampedScale = min(max(scale, 0.9), 1)
        let scaledSize = NSSize(
            width: targetFrame.width * clampedScale,
            height: targetFrame.height * clampedScale
        )
        return NSRect(
            x: targetFrame.midX - scaledSize.width / 2 + direction.x * travel,
            y: targetFrame.midY - scaledSize.height / 2 + direction.y * travel,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

enum DesktopLiquidMotion {
    // BetterDisplay-style anchored popovers establish their shell first and
    // let readable content settle inside it. Keep the frequent hover path
    // responsive while preserving the capsule-to-panel spatial connection.
    static let expandDuration: TimeInterval = 0.26
    static let collapseDuration: TimeInterval = 0.22
    static let contentEntranceDelay: TimeInterval = 0.05
    static let contentEntranceDuration: TimeInterval = 0.16
    static let morphDuration: TimeInterval = 0.24
    static let completionMorphCollapseDuration: TimeInterval = 0.24
    static let completionMarqueeOrbitDuration: TimeInterval = 1.8
    static let hoverDuration: TimeInterval = 0.14
    static let resizeDuration: TimeInterval = 0.30

    static func estimatedFrameCount(
        duration: TimeInterval,
        refreshRate: Int
    ) -> Int {
        Int((duration * Double(max(refreshRate, 1))).rounded(.up))
    }

    static func expandTiming() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
    }

    static func collapseTiming() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    static func hoverTiming() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    static func resizeTiming() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.77, 0, 0.175, 1)
    }

    static func completionMorphTiming() -> CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    }

    static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

struct DesktopWindowPresentationTransition: Equatable {
    private(set) var generation: UInt = 0
    private(set) var activeGeneration: UInt?

    var suppressesPositionSynchronization: Bool { activeGeneration != nil }

    mutating func begin() -> UInt {
        generation &+= 1
        activeGeneration = generation
        return generation
    }

    mutating func finish(_ candidate: UInt) -> Bool {
        guard activeGeneration == candidate else { return false }
        activeGeneration = nil
        return true
    }

    func isActive(_ candidate: UInt) -> Bool {
        activeGeneration == candidate
    }
}

enum DesktopQuotaSummaryStyle {
    static func textColor(lowestRemainingPercent percent: Int?) -> NSColor {
        guard let percent else { return .tertiaryLabelColor }
        if percent <= 20 {
            return NSColor.systemRed.withAlphaComponent(0.68)
        }
        if percent < 50 {
            return NSColor.systemOrange.withAlphaComponent(0.78)
        }
        return .tertiaryLabelColor
    }
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
        // A resolution or display-layout change can make a previously valid
        // panel larger than the new visible frame. Moving that frame alone is
        // insufficient: the min/max origin range becomes inverted and AppKit
        // can leave the entire title/header outside the reachable area.
        clamped.size.width = min(
            frame.width,
            visibleFrame.width + contentInsets.left + contentInsets.right
        )
        clamped.size.height = min(
            frame.height,
            visibleFrame.height + contentInsets.top + contentInsets.bottom
        )
        let minimumX = visibleFrame.minX - contentInsets.left
        let maximumX = visibleFrame.maxX - clamped.width + contentInsets.right
        let minimumY = visibleFrame.minY - contentInsets.bottom
        let maximumY = visibleFrame.maxY - clamped.height + contentInsets.top
        clamped.origin.x = min(max(frame.origin.x, minimumX), maximumX)
        clamped.origin.y = min(max(frame.origin.y, minimumY), maximumY)
        return clamped
    }
}

enum DesktopPanelAnchorLayout {
    static func anchor(fromPanelFrame frame: NSRect) -> NSPoint {
        NSPoint(x: frame.maxX, y: frame.maxY)
    }

    static func anchor(
        fromFloatingFrame frame: NSRect,
        floatingContentInset: CGFloat = DesktopFloatingButtonLayout.animationInset
    ) -> NSPoint {
        NSPoint(x: frame.maxX - floatingContentInset, y: frame.maxY - floatingContentInset)
    }

    static func panelFrame(anchoredTo anchor: NSPoint, panelSize: NSSize) -> NSRect {
        NSRect(
            x: anchor.x - panelSize.width,
            y: anchor.y - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
    }

    static func floatingFrame(
        anchoredTo anchor: NSPoint,
        floatingSize: NSSize,
        floatingContentInset: CGFloat = DesktopFloatingButtonLayout.animationInset
    ) -> NSRect {
        NSRect(
            x: anchor.x + floatingContentInset - floatingSize.width,
            y: anchor.y + floatingContentInset - floatingSize.height,
            width: floatingSize.width,
            height: floatingSize.height
        )
    }

    static func panelFrame(
        anchoredToFloatingPanel floatingFrame: NSRect,
        panelSize: NSSize,
        floatingContentInset: CGFloat = DesktopFloatingButtonLayout.animationInset
    ) -> NSRect {
        panelFrame(
            anchoredTo: anchor(
                fromFloatingFrame: floatingFrame,
                floatingContentInset: floatingContentInset
            ),
            panelSize: panelSize
        )
    }

    static func floatingFrame(
        anchoredToPanel panelFrame: NSRect,
        floatingSize: NSSize,
        floatingContentInset: CGFloat = DesktopFloatingButtonLayout.animationInset
    ) -> NSRect {
        floatingFrame(
            anchoredTo: anchor(fromPanelFrame: panelFrame),
            floatingSize: floatingSize,
            floatingContentInset: floatingContentInset
        )
    }
}

enum DesktopPanelLayout {
    enum Section: Equatable {
        case header
        case tasks
        case newTask
        case quota
        case footer
    }

    static let width: CGFloat = 480
    static let contentHorizontalInset: CGFloat = 16
    static let workItemHorizontalInset: CGFloat = 11
    static let contentWidth = width - contentHorizontalInset * 2
    static let conversationContentWidth = contentWidth - workItemHorizontalInset * 2
    static let emptyStateHeight = 52
    // Fixed chrome outside the task list: 30pt top inset, 24pt header,
    // three 11pt stack gaps, 32pt new-task field, 22pt quota row, and
    // 12pt bottom inset. Keep this tied to the actual constraints so the
    // window does not retain legacy height as blank space below the quota.
    static let fixedChromeHeight = 153

    static func contentSize(
        visibleItemCount: Int,
        sectionCount: Int = 0,
        showsEmptyState: Bool = true,
        conversationItemCount: Int = 0,
        contentMode: DesktopContentMode = .clean,
        conversationExtraHeightOverride: Int? = nil
    ) -> NSSize {
        let baseHeight = fixedChromeHeight
        let itemHeight = visibleItemCount > 0
            ? visibleItemCount * 62
            : (showsEmptyState ? emptyStateHeight : 0)
        let sectionHeight = sectionCount * 22
        let conversationHeight = conversationExtraHeightOverride
            ?? conversationItemCount * (contentMode == .clean ? 84 : 104)
        let height = CGFloat(baseHeight + itemHeight + sectionHeight + conversationHeight)
        return NSSize(width: width, height: min(height, contentMode == .clean ? 720 : 746))
    }

    static let sectionOrder: [Section] = [.header, .tasks, .newTask, .quota, .footer]
}

enum DesktopPanelTypography {
    static let activityAlignment: NSTextAlignment = .left
    static let metadataAlignment: NSTextAlignment = .left
    static let metadataFontSize: CGFloat = 11.5
    static let sectionFontSize: CGFloat = 11.5
}

struct DesktopQuotaPresentation: Equatable {
    let text: String
    let lowestRemainingPercent: Int?

    static func make(snapshot: WorkStatusSnapshot) -> Self {
        var parts: [String] = []
        var remaining: [Int] = []
        if let company = snapshot.companyQuota {
            parts.append("公司 \(company.remainingPercent)%")
            remaining.append(company.remainingPercent)
        } else {
            parts.append("公司额度待配置")
        }
        let codexParts = [
            snapshot.codexShortTermLimit.map { "5小时 \($0.remainingPercent)%" },
            snapshot.codexWeeklyLimit.map { "本周 \($0.remainingPercent)%" },
        ].compactMap { $0 }
        if !codexParts.isEmpty {
            parts.append("Codex " + codexParts.joined(separator: " / "))
        }
        remaining.append(contentsOf: [
            snapshot.codexShortTermLimit?.remainingPercent,
            snapshot.codexWeeklyLimit?.remainingPercent,
        ].compactMap { $0 })
        return Self(
            text: parts.joined(separator: " · "),
            lowestRemainingPercent: remaining.min()
        )
    }
}

enum WorkItemCardActionPolicy {
    static func showsPersistentPrimaryAction(status: WorkItemStatus) -> Bool {
        status == .waiting || status == .failed || status == .stale
    }
}

enum WorkItemCardActionLayout {
    static let primaryHeight: CGFloat = 28
    static let primaryMinimumWidth: CGFloat = 76
    static let iconHitSize: CGFloat = 28
    static let iconPointSize: CGFloat = 15
}

enum DesktopPanelResizePolicy {
    static let minimumFrameSize = NSSize(
        width: 480,
        // A collapsed section needs only its 22pt header. The true empty state
        // still requests its full 52pt height through `contentSize`; keeping
        // that height here makes AppKit force visible collapsed panels back to
        // 205pt and leaves 30pt of unused space below the quota row.
        height: CGFloat(DesktopPanelLayout.fixedChromeHeight + 22)
    )
    static let maximumFrameSize = NSSize(width: 720, height: 820)

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
    static let base = adaptive(dark: 0x2B2B2B, light: 0xF6F6F6)
    static let card = adaptive(dark: 0x3C3C3C, light: 0xFFFFFF)
    static let hoveredCard = adaptive(dark: 0x484848, light: 0xFBFBFB)
    static let input = adaptive(dark: 0x242424, light: 0xF7F7F7)
    static let stroke = adaptive(dark: 0x767676, light: 0xBABABA)

    private static func adaptive(dark: Int, light: Int) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}

enum DesktopLiquidGlassTokens {
    static func panelBaseAlpha(isDark: Bool) -> CGFloat { isDark ? 0.66 : 0.30 }
    static func cardAlpha(isDark: Bool, isHovering: Bool) -> CGFloat {
        if isHovering { return isDark ? 0.79 : 0.76 }
        return isDark ? 0.74 : 0.62
    }
    static func inputAlpha(isDark: Bool) -> CGFloat { isDark ? 0.84 : 0.68 }
    static func statusCapsuleFillAlpha(isDark: Bool) -> CGFloat { isDark ? 0.28 : 0.24 }
    static func dragHandleAlpha(
        isDark: Bool,
        isHovering: Bool,
        isPressed: Bool
    ) -> CGFloat {
        if isPressed { return isDark ? 0.62 : 0.68 }
        if isHovering { return isDark ? 0.50 : 0.58 }
        return isDark ? 0.32 : 0.46
    }
    static func capsuleAlpha(isDark: Bool, showsCompletion: Bool) -> CGFloat {
        if isDark { return showsCompletion ? 0.54 : 0.46 }
        return showsCompletion ? 0.76 : 0.68
    }
}

extension NSColor {
    func cgColor(resolvedFor appearance: NSAppearance) -> CGColor {
        var resolved = cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = cgColor
        }
        return resolved
    }
}

enum AppAppearanceMode: String, CaseIterable {
    case system, light, dark

    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum DesktopFloatingButtonLayout {
    static let size = NSSize(width: 108, height: 38)
    static let completionSize = NSSize(width: 288, height: 64)
    static let animationInset: CGFloat = 6
    static let dragHandleSize = NSSize(width: 26, height: 6)
    static let dragHandleGap: CGFloat = 3
    static let dragHandleBottomInset: CGFloat = 3
    static let windowContentInsets = NSEdgeInsets(
        top: animationInset,
        left: animationInset,
        bottom: dragHandleBottomInset,
        right: animationInset
    )
    static func canvasSize(for contentSize: NSSize) -> NSSize {
        NSSize(
            width: contentSize.width + animationInset * 2,
            height: contentSize.height
                + animationInset
                + dragHandleGap
                + dragHandleSize.height
                + dragHandleBottomInset
        )
    }
    static let canvasSize = canvasSize(for: size)
    static let completionCanvasSize = canvasSize(for: completionSize)
    static let cornerRadius: CGFloat = size.height / 2
    // Keep the anchored corner physically stable while the completion shell
    // changes size. A second radius transition makes the fixed top-right edge
    // look as if it bends during the morph.
    static let completionCornerRadius: CGFloat = cornerRadius
    static let statusDotSize: CGFloat = 8

    static func completionMorphCompactRect(
        in expandedBounds: NSRect,
        compactSize: NSSize = size
    ) -> NSRect {
        NSRect(
            x: expandedBounds.maxX - compactSize.width,
            y: expandedBounds.maxY - compactSize.height,
            width: compactSize.width,
            height: compactSize.height
        )
    }
}

struct DesktopFloatingButtonPresentation: Equatable {
    let displayText: String
    let detailText: String?
    let tintColor: NSColor
    let pulses: Bool
    let isRunning: Bool
    let accessibilityLabel: String

    static func make(items: [WorkItem], latestCompleted: WorkItem?) -> Self {
        let waitingCount = items.filter { $0.status == .waiting }.count
        let issueCount = items.filter { $0.status == .failed || $0.status == .stale }.count
        let runningCount = items.filter { $0.status == .running }.count
        let queuedCount = items.filter { $0.status == .queued }.count

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
        } else if runningCount > 0 {
            displayText = "\(runningCount) 运行"
            tintColor = .systemBlue
            pulses = true
        } else if queuedCount > 0 {
            displayText = "\(queuedCount) 排队"
            tintColor = .systemBlue
            pulses = false
        } else if latestCompleted != nil {
            displayText = "已完成"
            tintColor = .systemGreen
            pulses = false
        } else {
            displayText = "空闲"
            tintColor = .secondaryLabelColor
            pulses = false
        }

        let accessibilityLabel = "恢复 AI工作岛；当前\(displayText)"
        return Self(
            displayText: displayText,
            detailText: nil,
            tintColor: tintColor,
            pulses: pulses,
            isRunning: runningCount > 0,
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
            pages.append(Self.quota(
                displayText: "公司 \(quota.remainingPercent)%",
                remainingPercent: quota.remainingPercent,
                normalTint: .systemPurple,
                accessibilityText: "公司额度剩余\(quota.remainingPercent)%",
                isRunning: work.isRunning
            ))
        } else {
            pages.append(Self(
                displayText: "公司 待配置",
                detailText: nil,
                tintColor: .systemPurple,
                pulses: false,
                isRunning: work.isRunning,
                accessibilityLabel: "恢复 AI工作岛；公司额度待配置，请在 Edge 登录公司模型平台"
            ))
        }
        if let limit = snapshot.codexShortTermLimit {
            pages.append(quota(
                displayText: "5时 \(limit.remainingPercent)%",
                remainingPercent: limit.remainingPercent,
                normalTint: .systemTeal,
                accessibilityText: "5小时额度剩余\(limit.remainingPercent)%",
                isRunning: work.isRunning
            ))
        }
        if let limit = snapshot.codexWeeklyLimit {
            pages.append(quota(
                displayText: "周 \(limit.remainingPercent)%",
                remainingPercent: limit.remainingPercent,
                normalTint: .systemIndigo,
                accessibilityText: "周额度剩余\(limit.remainingPercent)%",
                isRunning: work.isRunning
            ))
        }
        return pages
    }

    static func recordingGuardian(_ state: VoiceMemoGuardianState, now: Date = Date()) -> Self {
        let isSilent = state.phase == .silence
        return Self(
            displayText: state.displayText(at: now),
            detailText: nil,
            tintColor: isSilent ? .systemOrange : .systemRed,
            pulses: !isSilent,
            isRunning: false,
            accessibilityLabel: isSilent
                ? "语音备忘录可能已结束；\(state.displayText(at: now))"
                : "语音备忘录正在录音；\(state.displayText(at: now))"
        )
    }

    private static func quota(
        displayText: String,
        remainingPercent: Int,
        normalTint: NSColor,
        accessibilityText: String,
        isRunning: Bool
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
            detailText: nil,
            tintColor: tintColor,
            pulses: false,
            isRunning: isRunning,
            accessibilityLabel: "恢复 AI工作岛；\(accessibilityText)"
        )
    }

    static func completion(item: WorkItem, result: String?) -> Self {
        let detail: String
        if let phaseCount = item.phaseCount, phaseCount > 0 {
            let phase = item.phase?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let phase, !phase.isEmpty {
                detail = "已完成 \(phaseCount)/\(phaseCount) · \(phase)"
            } else {
                detail = "已完成 \(phaseCount)/\(phaseCount) 个环节"
            }
        } else if let phase = item.phase?.trimmingCharacters(in: .whitespacesAndNewlines), !phase.isEmpty {
            detail = phase
        } else if let result = result?.trimmingCharacters(in: .whitespacesAndNewlines), !result.isEmpty {
            detail = result.components(separatedBy: .newlines).first ?? "任务已完成"
        } else {
            detail = "任务已完成，等待查看"
        }
        return Self(
            displayText: item.displayTitle,
            detailText: detail,
            tintColor: .systemGreen,
            pulses: false,
            isRunning: false,
            accessibilityLabel: "AI工作岛任务已完成；\(item.displayTitle)；\(detail)"
        )
    }
}

enum DesktopFloatingButtonMotion {
    static let entranceDuration: TimeInterval = 0.34
    static let transitionDuration: TimeInterval = 0.24
    static let completionContentDelay: TimeInterval = 0
    static let completionContentDuration: TimeInterval = 0.10
    static let completionContentStagger: TimeInterval = 0
    static let completionContentExitDuration: TimeInterval = 0.10
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
    static let collapseDelay: TimeInterval = 0.25
    static let panelTravelGrace: TimeInterval = 0.75
    static let layoutChangeGrace: TimeInterval = 0.6
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
        hasPendingAutoCollapse: Bool,
        suppressionExpiresAt: Date? = nil,
        now: Date = Date()
    ) -> Bool {
        guard suppressionExpiresAt.map({ now >= $0 }) ?? true else { return false }
        return shouldAutoCollapse(
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

    static func autoCollapseDelay(expandedAt: Date?, now: Date = Date()) -> TimeInterval {
        guard let expandedAt else { return collapseDelay }
        return max(collapseDelay, panelTravelGrace - now.timeIntervalSince(expandedAt))
    }
}

enum DesktopCompletionReminderBehavior {
    static let revealDuration: TimeInterval = 6

    static func newlyCompletedItemIDs(
        previous: WorkStatusSnapshot?,
        current: WorkStatusSnapshot
    ) -> Set<String> {
        guard let previous else { return [] }
        let previousStatuses = Dictionary(uniqueKeysWithValues: previous.items.map { ($0.id, $0.status) })
        let transitionedItemIDs: Set<String> = Set(current.items.compactMap { item -> String? in
            guard previousStatuses[item.id]?.isActiveWork == true,
                  item.status == .waiting || item.status == .completed else { return nil }
            return item.id
        })
        let currentItemIDs = Set(current.items.map(\.id))
        let disappearedCodexItemIDs: Set<String> = Set(previous.items.compactMap { item -> String? in
            guard item.id.hasPrefix("codex:"),
                  item.status.isActiveWork,
                  !currentItemIDs.contains(item.id) else { return nil }
            return item.id
        })
        return transitionedItemIDs.union(disappearedCodexItemIDs)
    }

    static func completedItem(
        previous: WorkStatusSnapshot?,
        current: WorkStatusSnapshot,
        matching itemIDs: Set<String>
    ) -> WorkItem? {
        let currentMatches = current.items
            .filter { itemIDs.contains($0.id) }
        let currentMatch = currentMatches.max { $0.updatedAt < $1.updatedAt }
        guard currentMatch == nil else { return currentMatch }
        return previous?.items
            .filter { itemIDs.contains($0.id) && $0.status.isActiveWork }
            .max { $0.updatedAt < $1.updatedAt }
    }
}

enum DesktopCompletionUIReviewMode: Equatable {
    case disabled
    case looping
    case held

    init(arguments: [String]) {
        if arguments.contains("--ui-review-completion-hold") {
            self = .held
        } else if arguments.contains("--ui-review-completion") {
            self = .looping
        } else {
            self = .disabled
        }
    }
}

struct DesktopFloatingButtonMotionSnapshot: Equatable {
    let root: Set<String>
    let shellMask: Set<String>
    let statusDot: Set<String>
    let statusLabel: Set<String>
    let detailLabel: Set<String>
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
    let activities: [String]?
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
        activities = item.activities
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

    static let defaultExpandedSections: Set<WorkSection> = [.active]
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
    private static let userPanelCenterXDefaultsKey = "desktopPanelUserCenterX"
    private static let userPanelCenterYDefaultsKey = "desktopPanelUserCenterY"
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
    var onStopRecordingSelected: (() -> Void)? {
        didSet { floatingButtonView.onStopRecording = onStopRecordingSelected }
    }
    var suppressesAutomaticReveals = false

    private let panel: NSPanel
    private let floatingPanel: NSPanel
    private let floatingButtonView = FloatingStatusButtonView()
    private let floatingDragHandleView = FloatingDragHandleView()
    private var floatingButtonWidthConstraint: NSLayoutConstraint!
    private var floatingButtonHeightConstraint: NSLayoutConstraint!
    private let titleLabel = NSTextField(labelWithString: "AI工作岛")
    private let statusCapsule = StatusCapsuleView()
    private let newTaskInputBackground = RoundedInputBackground()
    private let newTaskPromptField = PastedImageTextField(string: "")
    private let newTaskImageCountLabel = NSTextField(labelWithString: "")
    private let newTaskSendButton = FirstMouseButton()
    private let newTaskDirectoryButton = FirstMouseButton()
    private let quotaSummaryView = DesktopQuotaSummaryView()
    private let itemStack = NSStackView()
    private let footerLabel = NSTextField(labelWithString: "")
    private weak var panelContentStack: NSStackView?
    private var displayedItemIDs: [String]?
    private var displayedRowCount = 0
    private var lastStatuses: [String: WorkItemStatus] = [:]
    private var pendingSweepColors: [String: NSColor] = [:]
    private var expandedSections = WorkSection.defaultExpandedSections
    private var latestSnapshot: WorkStatusSnapshot?
    private var displayedContentSignature: DesktopPanelContentSignature?
    private var isMinimizedToFloatingButton = false
    private var didPositionFloatingPanel = false
    private var isHoverExpanded = false
    private var isPanelHovered = false
    private var pendingAutoCollapse: DispatchWorkItem?
    private var autoCollapseRequestID: UInt = 0
    private var hoverReconciliationTimer: Timer?
    private var autoCollapseSuppressionExpiresAt: Date?
    private var hoverExpandedAt: Date?
    private var pendingCompletionCollapse: DispatchWorkItem?
    private var completionUIReviewTimer: Timer?
    private var completionUIReviewMode: DesktopCompletionUIReviewMode = .disabled
    private var codexResults: [String: String] = [:]
    private var codexRows: [String: WorkItemRowView] = [:]
    private var displayMode: DesktopPanelMode = .background
    private var contentMode: DesktopContentMode = .clean
    private var isSynchronizingWindowPositions = false
    private var windowPresentationTransition = DesktopWindowPresentationTransition()
    private var panelResizeTransition = DesktopWindowPresentationTransition()
    private var isAutomaticallySizingPanel = false
    private var hasUserPreferredPanelWidth = false
    private var userPreferredPanelCenter: NSPoint?
    private var isPanelBeingResized = false
    private var isVisibilityRequested = false
    /// Single source of truth for both window states. AppKit may resize or retain
    /// the hidden window during a transition; neither state may inherit that stale frame.
    private var sharedTopRightAnchor: NSPoint?
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
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
        isVisibilityRequested = true
        cancelPendingAutoCollapse()
        stopHoverReconciliation()
        autoCollapseSuppressionExpiresAt = nil
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        applyDisplayMode(hoverExpanded: false)
        centerPanelOnActiveScreen()
        floatingPanel.orderOut(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(nil)
    }

    func setAppearanceMode(_ mode: AppAppearanceMode) {
        panel.appearance = mode.appearance
        floatingPanel.appearance = mode.appearance
        floatingButtonView.appearance = mode.appearance
        displayedContentSignature = nil
        displayedItemIDs = nil
        if let latestSnapshot { update(snapshot: latestSnapshot) }
        panel.contentView?.needsDisplay = true
        floatingPanel.contentView?.needsDisplay = true
    }

    /// Restores the panel through the same leave-to-collapse lifecycle used by
    /// the floating capsule. Explicitly reopening the app or enabling the panel
    /// must not leave it permanently expanded.
    func showAutoCollapsing() {
        show()
        isHoverExpanded = true
        hoverExpandedAt = Date()
        refreshPanelHoverState()
        startHoverReconciliationIfNeeded()
        scheduleAutoCollapseIfNeeded()
    }

    func showCollapsed() {
        isVisibilityRequested = true
        cancelPendingAutoCollapse()
        stopHoverReconciliation()
        autoCollapseSuppressionExpiresAt = nil
        isHoverExpanded = false
        isMinimizedToFloatingButton = true
        applyDisplayMode(hoverExpanded: false)
        restoreCompactFloatingButton()
        positionFloatingPanelForCollapsedState()
        panel.orderOut(nil)
        floatingPanel.alphaValue = 1
        floatingPanel.orderFrontRegardless()
    }

    func hide() {
        isVisibilityRequested = false
        cancelPendingAutoCollapse()
        stopHoverReconciliation()
        autoCollapseSuppressionExpiresAt = nil
        isHoverExpanded = false
        isMinimizedToFloatingButton = false
        cancelCompletionCapsule()
        applyDisplayMode(hoverExpanded: false)
        panel.orderOut(nil)
        floatingPanel.orderOut(nil)
    }

    func startCompletionUIReview(_ mode: DesktopCompletionUIReviewMode) {
        completionUIReviewTimer?.invalidate()
        completionUIReviewTimer = nil
        completionUIReviewMode = mode
        guard mode != .disabled else { return }

        showCollapsed()
        presentCompletionUIReview(holdsPresentation: mode == .held)
        guard mode == .looping else { return }

        let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.presentCompletionUIReview(holdsPresentation: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        completionUIReviewTimer = timer
    }

    private func presentCompletionUIReview(holdsPresentation: Bool) {
        pendingCompletionCollapse?.cancel()
        pendingCompletionCollapse = nil
        floatingButtonView.clearCompletion()
        floatingButtonView.showCompletion(
            item: WorkItem(
                id: "codex:completion-ui-review",
                source: "Codex",
                title: "工作岛状态动画",
                status: .completed,
                updatedAt: Date()
            ),
            result: "任务扩充状态已完成"
        )
        setFloatingContentSize(DesktopFloatingButtonLayout.completionSize, animated: true)
        floatingPanel.orderFrontRegardless()

        guard !holdsPresentation else { return }
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreCompactFloatingButton()
        }
        pendingCompletionCollapse = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopCompletionReminderBehavior.revealDuration,
            execute: workItem
        )
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        recoverAfterScreenConfigurationChange()
    }

    /// AppKit can leave a nonactivating panel ordered out or attached to a
    /// disconnected display after a display, resolution, or Space reconfigure.
    /// Reassert the requested presentation so "always in front" never means
    /// that both the dashboard and its capsule are absent.
    func recoverAfterScreenConfigurationChange() {
        guard isVisibilityRequested else { return }

        applyDisplayMode(hoverExpanded: isHoverExpanded && !isMinimizedToFloatingButton)
        floatingPanel.isFloatingPanel = true
        floatingPanel.level = .floating
        floatingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floatingPanel.hidesOnDeactivate = false
        panel.alphaValue = 1
        floatingPanel.alphaValue = 1

        if isMinimizedToFloatingButton {
            clampWindowToAvailableScreen(
                floatingPanel,
                contentInsets: DesktopFloatingButtonLayout.windowContentInsets
            )
            alignPanelToFloatingPanel()
            panel.orderOut(nil)
            floatingPanel.orderFrontRegardless()
        } else {
            clampWindowToAvailableScreen(panel)
            alignFloatingPanelToPanel()
            floatingPanel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }

    var panelIsVisibleForTesting: Bool { panel.isVisible }
    var panelFrameSizeForTesting: NSSize { panel.frame.size }
    var panelTaskArrangedSubviewCountForTesting: Int { itemStack.arrangedSubviews.count }
    var floatingPanelIsVisibleForTesting: Bool { floatingPanel.isVisible }
    var panelLevelForTesting: NSWindow.Level { panel.level }
    var floatingPanelLevelForTesting: NSWindow.Level { floatingPanel.level }
    var floatingPanelSizeForTesting: NSSize {
        DesktopFloatingButtonLayout.canvasSize(for: NSSize(
            width: floatingButtonWidthConstraint?.constant ?? DesktopFloatingButtonLayout.size.width,
            height: floatingButtonHeightConstraint?.constant ?? DesktopFloatingButtonLayout.size.height
        ))
    }
    var activityRowsFillLeadingEdgeForTesting: Bool {
        panel.contentView?.layoutSubtreeIfNeeded()
        return !codexRows.isEmpty
            && codexRows.values.allSatisfy(\.activityRowsFillLeadingEdgeForTesting)
    }
    var conversationRowsStayInsideCardForTesting: Bool {
        panel.contentView?.layoutSubtreeIfNeeded()
        return !codexRows.isEmpty
            && codexRows.values.allSatisfy(\.contentStaysInsideCardForTesting)
    }
    var conversationTitlesUseAvailableHeaderWidthForTesting: Bool {
        panel.contentView?.layoutSubtreeIfNeeded()
        return !codexRows.isEmpty
            && codexRows.values.allSatisfy(\.titleUsesAvailableHeaderWidthForTesting)
    }
    var conversationHoveredHeadersUseFullWidthForTesting: Bool {
        codexRows.values.forEach { $0.setHoveringForTesting(true) }
        panel.contentView?.layoutSubtreeIfNeeded()
        let result = !codexRows.isEmpty
            && codexRows.values.allSatisfy(\.headerUsesFullWidthForTesting)
        codexRows.values.forEach { $0.setHoveringForTesting(false) }
        return result
    }
    var floatingPanelFrameForTesting: NSRect { floatingPanel.frame }
    var floatingButtonMotionForTesting: DesktopFloatingButtonMotionSnapshot {
        floatingButtonView.motionSnapshot()
    }
    var completionCollapseIsScheduledForTesting: Bool { pendingCompletionCollapse != nil }
    var floatingButtonIsShowingCompletionForTesting: Bool {
        floatingButtonView.isCompletionVisibleForTesting()
    }
    var floatingButtonCompactVisualIsRestoredForTesting: Bool {
        floatingButtonView.compactVisualIsRestoredForTesting()
    }
    func startCompletionCollapseForTesting() { restoreCompactFloatingButton() }
    func interruptCompletionCollapseForTesting() {
        floatingButtonView.interruptCompletionShellCollapseForTesting()
    }
    var floatingPanelHasWindowShadowForTesting: Bool { floatingPanel.hasShadow }
    var sharedAnchorForTesting: NSPoint? { sharedTopRightAnchor }
    var userPreferredPanelCenterForTesting: NSPoint? { userPreferredPanelCenter }

    func setCollapsedFrameForTesting(_ frame: NSRect) {
        setFrame(frame, for: floatingPanel)
        sharedTopRightAnchor = DesktopPanelAnchorLayout.anchor(fromFloatingFrame: frame)
        didPositionFloatingPanel = true
    }

    func setCodexResultForTesting(_ result: String, itemID: String) {
        codexResults[itemID] = result
    }

    func beginPresentationTransitionForTesting() -> UInt {
        windowPresentationTransition.begin()
    }

    func activateFloatingButtonForTesting() {
        activateFloatingButton(hoverExpanded: true)
    }

    func finishPresentationTransitionForTesting(_ generation: UInt) {
        _ = windowPresentationTransition.finish(generation)
    }

    func notifyPanelMoveForTesting(to frame: NSRect) {
        panel.setFrame(frame, display: false)
        windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
    }

    func runExpandCollapseCycleForTesting() async {
        showCollapsed()
        activateFloatingButton(hoverExpanded: true)
        await waitForPresentationTransitionForTesting()
        minimizeToFloatingButton()
        await waitForPresentationTransitionForTesting()
    }

    private func waitForPresentationTransitionForTesting() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while windowPresentationTransition.suppressesPositionSynchronization,
              clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    func orderWindowsOutForTesting() {
        panel.orderOut(nil)
        floatingPanel.orderOut(nil)
    }

    func update(snapshot: WorkStatusSnapshot) {
        let previousSnapshot = latestSnapshot
        let newlyCompletedItemIDs = DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
            previous: previousSnapshot,
            current: snapshot
        )
        latestSnapshot = snapshot
        floatingButtonView.update(snapshot: snapshot)
        if !suppressesAutomaticReveals {
            revealCompletedItemsIfNeeded(
                newlyCompletedItemIDs,
                previousSnapshot: previousSnapshot,
                currentSnapshot: snapshot
            )
        }
        captureStatusEffects(in: snapshot)
        updateQuotaViews(snapshot: snapshot)
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
        guard displayedItemIDs != nil else {
            self.displayedItemIDs = visibleIDs
            displayedRowCount = layout.rowCount
            displayedContentSignature = contentSignature
            apply(snapshot: snapshot, resizeImmediately: true)
            return
        }
        self.displayedItemIDs = visibleIDs
        displayedRowCount = layout.rowCount
        displayedContentSignature = contentSignature
        apply(snapshot: snapshot, resizeImmediately: true)
    }

    func updateRecordingGuardian(_ state: VoiceMemoGuardianState?) {
        if state != nil {
            pendingCompletionCollapse?.cancel()
            pendingCompletionCollapse = nil
            floatingButtonView.clearCompletion()
            setFloatingContentSize(DesktopFloatingButtonLayout.size, animated: true)
        }
        floatingButtonView.updateRecordingGuardian(state)
    }

    func updateRecordingStopInProgress(_ isInProgress: Bool) {
        floatingButtonView.updateRecordingStopInProgress(isInProgress)
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
        // Removing a card can shrink the panel out from under the pointer. That
        // is a layout change, not an intentional mouse leave. Keep the panel
        // open through the resize animation, then resume real pointer
        // reconciliation even if the pointer never re-enters the smaller panel.
        autoCollapseSuppressionExpiresAt = Date().addingTimeInterval(
            DesktopFloatingHoverBehavior.layoutChangeGrace
        )
        cancelPendingAutoCollapse()
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
        let conversationMeasurementWidth = DesktopConversationLayout.resolvedMeasurementWidth(
            itemStackWidth: itemStack.bounds.width,
            panelContentWidth: panel.contentLayoutRect.width
        )
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
                        contentMode: contentMode,
                        measurementWidth: conversationMeasurementWidth
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
                    row.heightAnchor.constraint(equalToConstant: row.requiredHeight).isActive = true
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
                    showsEmptyState: snapshot.items.isEmpty,
                    conversationItemCount: layout.sections
                        .flatMap(\.items)
                        .filter { $0.id.hasPrefix("codex:") }
                        .count,
                    contentMode: contentMode,
                    conversationExtraHeightOverride: layout.sections
                        .flatMap(\.items)
                        .filter { $0.id.hasPrefix("codex:") }
                        .reduce(into: 0) { total, item in
                            total += DesktopConversationLayout.extraHeight(
                                item: item,
                                lastAssistantResult: codexResults[item.id],
                                contentMode: contentMode,
                                measurementWidth: conversationMeasurementWidth
                            )
                        }
                ),
                currentContentSize: panel.contentView?.bounds.size ?? panel.contentLayoutRect.size,
                hasUserPreferredSize: hasUserPreferredPanelWidth
            )
            isAutomaticallySizingPanel = true
            if let targetFrame = panelFrameForPresentation(forContentSize: fittedContentSize) {
                resizeExpandedPanel(to: targetFrame)
            } else {
                panel.setContentSize(fittedContentSize)
            }
            isAutomaticallySizingPanel = false
        }
    }

    private func resizeExpandedPanel(to targetFrame: NSRect) {
        guard panel.frame != targetFrame else { return }
        guard panel.isVisible,
              !isMinimizedToFloatingButton,
              !DesktopLiquidMotion.reducesMotion else {
            setFrame(targetFrame, for: panel)
            return
        }

        isSynchronizingWindowPositions = true
        let resizeGeneration = panelResizeTransition.begin()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesktopLiquidMotion.resizeDuration
            context.timingFunction = DesktopLiquidMotion.resizeTiming()
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      panelResizeTransition.finish(resizeGeneration) else { return }
                isSynchronizingWindowPositions = false
            }
        }
    }

    private func updateQuotaViews(snapshot: WorkStatusSnapshot) {
        quotaSummaryView.update(DesktopQuotaPresentation.make(snapshot: snapshot))
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
              !windowPresentationTransition.suppressesPositionSynchronization,
              let window = notification.object as? NSWindow,
              !(window === panel && isAutomaticallySizingPanel),
              let screen = screenMostCovered(by: window.frame) else { return }
        let contentInsets: NSEdgeInsets = window === floatingPanel
            ? DesktopFloatingButtonLayout.windowContentInsets
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
            userPreferredPanelCenter = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
            persistUserPreferredPanelPosition()
        } else if window === floatingPanel {
            sharedTopRightAnchor = DesktopPanelAnchorLayout.anchor(fromFloatingFrame: floatingPanel.frame)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isSynchronizingWindowPositions,
              !windowPresentationTransition.suppressesPositionSynchronization,
              notification.object as? NSWindow === panel else { return }
        guard !isAutomaticallySizingPanel else { return }
        guard panel.isVisible else { return }
        hasUserPreferredPanelWidth = true
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
        hasUserPreferredPanelWidth = true
        persistUserPreferredPanelSize()
        alignFloatingPanelToPanel()
        refreshPanelHoverState()
        scheduleAutoCollapseIfNeeded()
    }

    private func configurePanel() {
        panel.delegate = self
        panel.title = "AI工作岛"
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
        restoreUserPreferredPanelPosition()

        let materialView = PanelBackgroundView()
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
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        statusCapsule.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusCapsule.setContentCompressionResistancePriority(.required, for: .vertical)

        let header = NSStackView(views: [titleLabel, NSView(), statusCapsule])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        header.heightAnchor.constraint(
            greaterThanOrEqualToConstant: DesktopPanelHeaderLayout.minimumHeight
        ).isActive = true

        newTaskPromptField.placeholderString = "新建任务…"
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

        quotaSummaryView.heightAnchor.constraint(equalToConstant: 22).isActive = true

        itemStack.orientation = .vertical
        itemStack.alignment = .leading
        itemStack.spacing = 6
        itemStack.distribution = .fill
        // The panel may temporarily be taller than its current content (for example
        // after restoring a user-resized window). Keep rows at their measured
        // content height instead of letting NSStackView distribute that surplus
        // into the cards. Any spare room belongs below the list.
        itemStack.setHuggingPriority(.required, for: .vertical)
        itemStack.setContentCompressionResistancePriority(.required, for: .vertical)

        footerLabel.font = .systemFont(ofSize: 10.5)
        footerLabel.textColor = .secondaryLabelColor
        footerLabel.lineBreakMode = .byTruncatingMiddle

        let contentStack = NSStackView(views: DesktopPanelLayout.sectionOrder.map { section in
            switch section {
            case .header: header
            case .tasks: itemStack
            case .newTask: newTaskInputBackground
            case .quota: quotaSummaryView
            case .footer: footerLabel
            }
        })
        contentStack.orientation = .vertical
        panelContentStack = contentStack
        contentStack.alignment = .leading
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
            header.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            itemStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            newTaskInputBackground.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            quotaSummaryView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            footerLabel.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
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
        autoCollapseSuppressionExpiresAt = nil
        isHoverExpanded = false
        isMinimizedToFloatingButton = true
        restoreCompactFloatingButton()
        positionFloatingPanelForCollapsedState()
        floatingButtonView.suppressHoverActivationUntilPointerExit(
            floatingPanel.frame.contains(NSEvent.mouseLocation)
        )
        hoverExpandedAt = nil
        let reduceMotion = DesktopLiquidMotion.reducesMotion
        guard !reduceMotion else {
            panel.orderOut(nil)
            applyDisplayMode(hoverExpanded: false)
            floatingPanel.orderFrontRegardless()
            return
        }

        if !floatingPanel.isVisible {
            floatingPanel.alphaValue = 0
            floatingPanel.orderFrontRegardless()
        }
        floatingButtonView.playEntrance()
        let restingPanelFrame = panel.frame
        let recedingPanelFrame = DesktopPanelTransitionMotion.frameTowardSource(
            targetFrame: restingPanelFrame,
            sourceFrame: floatingPanel.frame,
            travel: DesktopPanelTransitionMotion.collapseTravel,
            scale: DesktopPanelTransitionMotion.collapseSourceScale
        )
        let transitionGeneration = windowPresentationTransition.begin()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesktopLiquidMotion.collapseDuration
            context.timingFunction = DesktopLiquidMotion.collapseTiming()
            panel.animator().alphaValue = 0
            panel.animator().setFrame(recedingPanelFrame, display: true)
            panelContentStack?.animator().alphaValue = 0
            floatingPanel.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard windowPresentationTransition.finish(transitionGeneration) else { return }
                // Hover can restore the panel before this shrinking animation finishes.
                // Do not let the stale completion hide the newly restored panel.
                guard DesktopFloatingPanelTransition.shouldFinishMinimizing(
                    isMinimizedToFloatingButton: isMinimizedToFloatingButton
                ) else {
                    panel.alphaValue = 1
                    setFrame(restingPanelFrame, for: panel)
                    return
                }
                panel.orderOut(nil)
                panel.alphaValue = 1
                panelContentStack?.alphaValue = 1
                setFrame(restingPanelFrame, for: panel)
                applyDisplayMode(hoverExpanded: false)
            }
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
        floatingPanel.hasShadow = false
        floatingPanel.animationBehavior = .utilityWindow
        let canvas = NSView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.canvasSize))
        canvas.wantsLayer = true
        canvas.layer?.backgroundColor = NSColor.clear.cgColor
        floatingButtonView.translatesAutoresizingMaskIntoConstraints = false
        floatingDragHandleView.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(floatingButtonView)
        canvas.addSubview(floatingDragHandleView)
        floatingButtonWidthConstraint = floatingButtonView.widthAnchor.constraint(
            equalToConstant: DesktopFloatingButtonLayout.size.width
        )
        floatingButtonHeightConstraint = floatingButtonView.heightAnchor.constraint(
            equalToConstant: DesktopFloatingButtonLayout.size.height
        )
        NSLayoutConstraint.activate([
            floatingButtonView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            floatingButtonView.topAnchor.constraint(
                equalTo: canvas.topAnchor,
                constant: DesktopFloatingButtonLayout.animationInset
            ),
            floatingButtonWidthConstraint,
            floatingButtonHeightConstraint,
            floatingDragHandleView.centerXAnchor.constraint(equalTo: canvas.centerXAnchor),
            floatingDragHandleView.topAnchor.constraint(
                equalTo: floatingButtonView.bottomAnchor,
                constant: DesktopFloatingButtonLayout.dragHandleGap
            ),
            floatingDragHandleView.widthAnchor.constraint(
                equalToConstant: DesktopFloatingButtonLayout.dragHandleSize.width
            ),
            floatingDragHandleView.heightAnchor.constraint(
                equalToConstant: DesktopFloatingButtonLayout.dragHandleSize.height
            ),
        ])
        floatingPanel.contentView = canvas
        floatingButtonView.onActivate = { [weak self] in
            self?.activateFloatingButton(hoverExpanded: true)
        }
        floatingButtonView.onHoverEntered = { [weak self] in
            self?.activateFloatingButton(hoverExpanded: true)
        }
        floatingDragHandleView.onDragBegan = { [weak self] in
            self?.floatingButtonView.suppressHoverActivationUntilPointerExit(true)
        }
    }

    private func activateFloatingButton(hoverExpanded: Bool) {
        guard completionUIReviewMode == .disabled else { return }
        guard DesktopFloatingPanelTransition.shouldActivate(
            isMinimizedToFloatingButton: isMinimizedToFloatingButton,
            isFloatingPanelVisible: floatingPanel.isVisible
        ) else { return }
        cancelCompletionCapsule()
        let targetPanelFrame = panelFrameForPresentation(forOuterSize: panel.frame.size) ?? panel.frame
        let reduceMotion = DesktopLiquidMotion.reducesMotion
        guard !reduceMotion else {
            setFrame(targetPanelFrame, for: panel)
            isMinimizedToFloatingButton = false
            isHoverExpanded = hoverExpanded
            hoverExpandedAt = hoverExpanded ? Date() : nil
            applyDisplayMode(hoverExpanded: hoverExpanded)
            floatingPanel.orderOut(nil)
            panel.orderFrontRegardless()
            panel.makeFirstResponder(nil)
            refreshPanelHoverState()
            startHoverReconciliationIfNeeded()
            return
        }

        isMinimizedToFloatingButton = false
        isHoverExpanded = hoverExpanded
        hoverExpandedAt = hoverExpanded ? Date() : nil
        applyDisplayMode(hoverExpanded: hoverExpanded)
        setFrame(
            DesktopPanelTransitionMotion.frameTowardSource(
                targetFrame: targetPanelFrame,
                sourceFrame: floatingPanel.frame,
                travel: DesktopPanelTransitionMotion.expandTravel,
                scale: DesktopPanelTransitionMotion.expandSourceScale
            ),
            for: panel
        )
        panel.alphaValue = 0
        panelContentStack?.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeFirstResponder(nil)
        refreshPanelHoverState()
        startHoverReconciliationIfNeeded()
        floatingButtonView.playExit()
        let transitionGeneration = windowPresentationTransition.begin()
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopLiquidMotion.contentEntranceDelay
        ) { [weak self] in
            guard let self,
                  windowPresentationTransition.isActive(transitionGeneration),
                  !isMinimizedToFloatingButton else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = DesktopLiquidMotion.contentEntranceDuration
                context.timingFunction = DesktopLiquidMotion.expandTiming()
                panelContentStack?.animator().alphaValue = 1
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesktopLiquidMotion.expandDuration
            context.timingFunction = DesktopLiquidMotion.expandTiming()
            panel.animator().alphaValue = 1
            panel.animator().setFrame(targetPanelFrame, display: true)
            floatingPanel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard windowPresentationTransition.finish(transitionGeneration) else { return }
                panelContentStack?.alphaValue = 1
                floatingPanel.orderOut(nil)
                floatingPanel.alphaValue = 1
            }
        }
    }

    private func revealCompletedItemsIfNeeded(
        _ itemIDs: Set<String>,
        previousSnapshot: WorkStatusSnapshot?,
        currentSnapshot: WorkStatusSnapshot
    ) {
        guard completionUIReviewMode == .disabled,
              isMinimizedToFloatingButton,
              let completedItem = DesktopCompletionReminderBehavior.completedItem(
                previous: previousSnapshot,
                current: currentSnapshot,
                matching: itemIDs
              ) else { return }
        let priorItem = previousSnapshot?.items.first { $0.id == completedItem.id }
        floatingButtonView.showCompletion(
            item: priorItem ?? completedItem,
            result: codexResults[completedItem.id]
        )
        setFloatingContentSize(DesktopFloatingButtonLayout.completionSize, animated: true)
        floatingPanel.orderFrontRegardless()

        pendingCompletionCollapse?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restoreCompactFloatingButton()
        }
        pendingCompletionCollapse = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopCompletionReminderBehavior.revealDuration,
            execute: workItem
        )
    }

    private func cancelCompletionCapsule() {
        pendingCompletionCollapse?.cancel()
        pendingCompletionCollapse = nil
        floatingButtonView.clearCompletion()
    }

    private func restoreCompactFloatingButton() {
        pendingCompletionCollapse?.cancel()
        pendingCompletionCollapse = nil
        guard floatingButtonView.isCompletionVisibleForTesting(),
              !DesktopLiquidMotion.reducesMotion else {
            floatingButtonView.clearCompletion()
            setFloatingContentSize(DesktopFloatingButtonLayout.size, animated: false)
            return
        }
        setFloatingContentSize(
            DesktopFloatingButtonLayout.size,
            animated: true
        ) { [weak self] in
            self?.floatingButtonView.clearCompletion()
        }
    }

    private func setFloatingContentSize(
        _ contentSize: NSSize,
        animated: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard floatingButtonWidthConstraint != nil, floatingButtonHeightConstraint != nil else { return }
        let canvasSize = DesktopFloatingButtonLayout.canvasSize(for: contentSize)
        let contentAlreadyMatches = floatingButtonWidthConstraint.constant == contentSize.width
            && floatingButtonHeightConstraint.constant == contentSize.height
        let frameAlreadyMatches = floatingPanel.frame.size == canvasSize
        guard !contentAlreadyMatches || !frameAlreadyMatches else { return }
        let anchor = sharedTopRightAnchor
            ?? DesktopPanelAnchorLayout.anchor(fromFloatingFrame: floatingPanel.frame)
        sharedTopRightAnchor = anchor
        let targetFrame = DesktopPanelAnchorLayout.floatingFrame(
            anchoredTo: anchor,
            floatingSize: canvasSize
        )
        if frameAlreadyMatches {
            applyFloatingContentSizeConstraints(contentSize)
            floatingPanel.contentView?.layoutSubtreeIfNeeded()
        } else if animated, !DesktopLiquidMotion.reducesMotion {
            let isExpanding = canvasSize.width > floatingPanel.frame.width
            if isExpanding {
                floatingButtonView.prepareCompletionShellExpansion(
                    from: DesktopFloatingButtonLayout.size,
                    to: contentSize
                )
                applyFloatingContentSizeConstraints(contentSize)
                setFrame(targetFrame, for: floatingPanel)
                floatingPanel.contentView?.layoutSubtreeIfNeeded()
                floatingButtonView.playPreparedCompletionShellExpansion()
                floatingDragHandleView.playCompletionExpansion(
                    horizontalTravel: (contentSize.width - DesktopFloatingButtonLayout.size.width) / 2,
                    duration: DesktopLiquidMotion.morphDuration
                )
                completion?()
                return
            }
            let horizontalTravel = (
                DesktopFloatingButtonLayout.completionSize.width - contentSize.width
            ) / 2
            floatingButtonView.playCompletionShellCollapse(
                to: contentSize
            ) { [weak self] in
                self?.finishFloatingContentCollapse(
                    contentSize: contentSize,
                    targetFrame: targetFrame,
                    completion: completion
                )
            }
            floatingDragHandleView.playCompletionCollapse(
                horizontalTravel: horizontalTravel,
                duration: DesktopLiquidMotion.completionMorphCollapseDuration
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + DesktopLiquidMotion.completionMorphCollapseDuration + 0.08
            ) { [weak self] in
                self?.finishFloatingContentCollapse(
                    contentSize: contentSize,
                    targetFrame: targetFrame,
                    completion: completion
                )
            }
        } else {
            applyFloatingContentSizeConstraints(contentSize)
            setFrame(targetFrame, for: floatingPanel)
            floatingPanel.contentView?.layoutSubtreeIfNeeded()
            completion?()
        }
    }

    private func finishFloatingContentCollapse(
        contentSize: NSSize,
        targetFrame: NSRect,
        completion: (() -> Void)?
    ) {
        let contentStillExpanded = floatingButtonWidthConstraint.constant != contentSize.width
            || floatingButtonHeightConstraint.constant != contentSize.height
        let frameStillExpanded = floatingPanel.frame != targetFrame
        guard contentStillExpanded || frameStillExpanded else { return }
        applyFloatingContentSizeConstraints(contentSize)
        setFrame(targetFrame, for: floatingPanel)
        floatingPanel.contentView?.layoutSubtreeIfNeeded()
        floatingDragHandleView.finishCompletionTransition()
        completion?()
    }

    private func applyFloatingContentSizeConstraints(_ contentSize: NSSize) {
        floatingButtonWidthConstraint.constant = contentSize.width
        floatingButtonHeightConstraint.constant = contentSize.height
    }

    private func setPanelHovering(_ isHovering: Bool) {
        isPanelHovered = isHovering
        if isHovering {
            autoCollapseSuppressionExpiresAt = nil
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
            hasPendingAutoCollapse: pendingAutoCollapse != nil,
            suppressionExpiresAt: autoCollapseSuppressionExpiresAt
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
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopFloatingHoverBehavior.autoCollapseDelay(
                expandedAt: hoverExpandedAt
            ),
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
        guard width > 0 else { return }
        let size = DesktopPanelResizePolicy.clampedFrameSize(
            NSSize(width: width, height: panel.frame.height)
        )
        var frame = panel.frame
        frame.size.width = size.width
        panel.setFrame(frame, display: false)
        hasUserPreferredPanelWidth = true
    }

    private func persistUserPreferredPanelSize() {
        let size = DesktopPanelResizePolicy.clampedFrameSize(panel.frame.size)
        UserDefaults.standard.set(size.width, forKey: Self.userPanelWidthDefaultsKey)
    }

    private func restoreUserPreferredPanelPosition() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.userPanelCenterXDefaultsKey) != nil,
              defaults.object(forKey: Self.userPanelCenterYDefaultsKey) != nil else { return }
        userPreferredPanelCenter = NSPoint(
            x: defaults.double(forKey: Self.userPanelCenterXDefaultsKey),
            y: defaults.double(forKey: Self.userPanelCenterYDefaultsKey)
        )
    }

    private func persistUserPreferredPanelPosition() {
        guard let userPreferredPanelCenter else { return }
        let defaults = UserDefaults.standard
        defaults.set(userPreferredPanelCenter.x, forKey: Self.userPanelCenterXDefaultsKey)
        defaults.set(userPreferredPanelCenter.y, forKey: Self.userPanelCenterYDefaultsKey)
    }

    private func positionFloatingPanelForCollapsedState() {
        guard !didPositionFloatingPanel else {
            return
        }
        let size = DesktopFloatingButtonLayout.canvasSize
        if panel.frame.origin != .zero {
            floatingPanel.setFrame(
                DesktopPanelAnchorLayout.floatingFrame(
                    anchoredToPanel: panel.frame,
                    floatingSize: size
                ),
                display: false
            )
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
            let visibleFrame = DesktopWindowVisibility.clampedFrame(
                floatingPanel.frame,
                in: screen.visibleFrame,
                contentInsets: DesktopFloatingButtonLayout.windowContentInsets
            )
            floatingPanel.setFrameOrigin(visibleFrame.origin)
        }
        didPositionFloatingPanel = true
    }

    private func centerPanelOnActiveScreen() {
        guard let frame = panelFrameForPresentation(forOuterSize: panel.frame.size) else { return }
        setFrame(frame, for: panel)
    }

    private func panelFrameForPresentation(forContentSize contentSize: NSSize) -> NSRect? {
        let outerSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        return panelFrameForPresentation(forOuterSize: outerSize)
    }

    private func panelFrameForPresentation(forOuterSize outerSize: NSSize) -> NSRect? {
        let fallbackScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
        guard let fallbackVisibleFrame = fallbackScreen?.visibleFrame else { return nil }
        let baseFrame: NSRect
        if let userPreferredPanelCenter {
            baseFrame = DesktopPanelRememberedPosition.restoredFrame(
                panelSize: outerSize,
                center: userPreferredPanelCenter,
                visibleFrames: NSScreen.screens.map(\.visibleFrame),
                fallbackVisibleFrame: fallbackVisibleFrame
            )
        } else if let centered = centeredPanelFrame(forOuterSize: outerSize) {
            baseFrame = centered
        } else {
            return nil
        }
        let topAligned = DesktopPanelCapsuleTopAlignment.alignedFrame(
            baseFrame,
            toFloatingFrame: floatingPanel.frame
        )
        let targetVisibleFrame = screenMostCovered(by: floatingPanel.frame)?.visibleFrame
            ?? fallbackVisibleFrame
        return DesktopWindowVisibility.clampedFrame(topAligned, in: targetVisibleFrame)
    }

    private func centeredPanelFrame(forContentSize contentSize: NSSize) -> NSRect? {
        let outerSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        return centeredPanelFrame(forOuterSize: outerSize)
    }

    private func centeredPanelFrame(forOuterSize outerSize: NSSize) -> NSRect? {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? screenMostCovered(by: panel.frame)
            ?? screenMostCovered(by: floatingPanel.frame)
            ?? NSScreen.main
        guard let screen else { return nil }
        return DesktopPanelCenterLayout.centeredFrame(
            panelSize: outerSize,
            in: screen.visibleFrame
        )
    }

    private func alignPanelToFloatingPanel() {
        let anchor = sharedTopRightAnchor
            ?? DesktopPanelAnchorLayout.anchor(fromFloatingFrame: floatingPanel.frame)
        sharedTopRightAnchor = anchor
        setFrame(
            DesktopPanelAnchorLayout.panelFrame(anchoredTo: anchor, panelSize: panel.frame.size),
            for: panel
        )
    }

    private func alignFloatingPanelToPanel() {
        let anchor = sharedTopRightAnchor
            ?? DesktopPanelAnchorLayout.anchor(fromPanelFrame: panel.frame)
        sharedTopRightAnchor = anchor
        setFrame(
            DesktopPanelAnchorLayout.floatingFrame(
                anchoredTo: anchor,
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

    private func clampWindowToAvailableScreen(
        _ window: NSWindow,
        contentInsets: NSEdgeInsets = DesktopWindowEdgeSnap.noInsets
    ) {
        let coveredScreen = NSScreen.screens
            .map { screen in
                let intersection = screen.visibleFrame.intersection(window.frame)
                let area: CGFloat = intersection.isNull ? 0 : intersection.width * intersection.height
                return (screen: screen, area: area)
            }
            .max { lhs, rhs in lhs.area < rhs.area }
        let targetScreen = coveredScreen.flatMap { $0.area > 0 ? $0.screen : nil } ?? NSScreen.main
        guard let targetScreen else { return }
        let frame = DesktopWindowVisibility.clampedFrame(
            window.frame,
            in: targetScreen.visibleFrame,
            contentInsets: contentInsets
        )
        setFrame(frame, for: window)
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
    static let hoverActivationDelay: TimeInterval = 0
    var onActivate: (() -> Void)?
    var onHoverEntered: (() -> Void)?
    var onStopRecording: (() -> Void)?

    private let statusDot = NSView()
    private let statusHalo = NSView()
    private let recordingWaveform = RecordingWaveformView()
    private let statusLabel = NSTextField(labelWithString: "空闲")
    private let detailLabel = NSTextField(labelWithString: "")
    private let stopRecordingButton = NSButton()
    private var normalStatusCenterConstraint: NSLayoutConstraint?
    private var completionStatusTopConstraint: NSLayoutConstraint?
    private var normalStatusHaloCenterConstraint: NSLayoutConstraint?
    private var completionStatusHaloTopConstraint: NSLayoutConstraint?
    private var normalStatusLabelTrailingConstraint: NSLayoutConstraint?
    private var recordingStatusLabelTrailingConstraint: NSLayoutConstraint?
    private let ambientLayer = CAGradientLayer()
    private let borderContainerLayer = CALayer()
    private let borderGradientLayer = CAGradientLayer()
    private let borderMaskLayer = CAShapeLayer()
    private let rippleLayer = CAShapeLayer()
    private let sheenLayer = CAGradientLayer()
    private let glassHighlightLayer = CAGradientLayer()
    private let completionShellMaskLayer = CALayer()
    private var trackingAreaReference: NSTrackingArea?
    private var currentTintColor = NSColor.controlAccentColor
    private var currentPresentation: DesktopFloatingButtonPresentation?
    private var carouselPresentations: [DesktopFloatingButtonPresentation] = []
    private var carouselIndex = 0
    private var carouselTimer: Timer?
    private var recordingGuardianState: VoiceMemoGuardianState?
    private var completionPresentation: DesktopFloatingButtonPresentation?
    private var isRecordingStopInProgress = false
    private var isHovering = false
    private var suppressesHoverActivationUntilExit = false
    private var pendingHoverActivation: DispatchWorkItem?
    private var completionShellAnimationGeneration: UInt = 0
    private var completionContentAnimationGeneration: UInt = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        alphaValue = 0.96
        wantsLayer = true
        layer?.cornerRadius = DesktopFloatingButtonLayout.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.75
        layer?.masksToBounds = true
        applyAppearanceColors()

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
        borderGradientLayer.colors = [
            NSColor.clear.cgColor,
            NSColor.white.cgColor,
            NSColor.systemCyan.withAlphaComponent(0.90).cgColor,
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
        ]
        borderGradientLayer.locations = [0, 0.04, 0.22, 0.58, 1]
        borderContainerLayer.opacity = 0
        borderMaskLayer.fillColor = NSColor.clear.cgColor
        borderMaskLayer.strokeColor = NSColor.white.cgColor
        borderMaskLayer.lineWidth = 2.25
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
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.maximumNumberOfLines = 1
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        detailLabel.isHidden = true
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailLabel)
        stopRecordingButton.bezelStyle = .inline
        stopRecordingButton.isBordered = false
        stopRecordingButton.image = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: "停止录音")
        stopRecordingButton.contentTintColor = .systemRed
        stopRecordingButton.toolTip = "停止录音并保留"
        stopRecordingButton.target = self
        stopRecordingButton.action = #selector(stopRecording)
        stopRecordingButton.translatesAutoresizingMaskIntoConstraints = false
        stopRecordingButton.isHidden = true
        addSubview(stopRecordingButton)
        normalStatusLabelTrailingConstraint = statusLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: trailingAnchor,
            constant: -10
        )
        recordingStatusLabelTrailingConstraint = statusLabel.trailingAnchor.constraint(
            lessThanOrEqualTo: stopRecordingButton.leadingAnchor,
            constant: -2
        )
        recordingStatusLabelTrailingConstraint?.isActive = false
        normalStatusCenterConstraint = statusLabel.centerYAnchor.constraint(
            equalTo: centerYAnchor,
            constant: -0.5
        )
        completionStatusTopConstraint = statusLabel.topAnchor.constraint(
            equalTo: topAnchor,
            constant: 13
        )
        completionStatusTopConstraint?.isActive = false
        normalStatusHaloCenterConstraint = statusHalo.centerYAnchor.constraint(equalTo: centerYAnchor)
        completionStatusHaloTopConstraint = statusHalo.topAnchor.constraint(
            equalTo: topAnchor,
            constant: 5
        )
        completionStatusHaloTopConstraint?.isActive = false
        NSLayoutConstraint.activate([
            statusHalo.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            normalStatusHaloCenterConstraint!,
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
            statusLabel.leadingAnchor.constraint(equalTo: statusHalo.trailingAnchor, constant: 6),
            normalStatusCenterConstraint!,
            normalStatusLabelTrailingConstraint!,
            detailLabel.leadingAnchor.constraint(equalTo: statusLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            detailLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 3),
            stopRecordingButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stopRecordingButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopRecordingButton.widthAnchor.constraint(equalToConstant: 18),
            stopRecordingButton.heightAnchor.constraint(equalToConstant: 18),
        ])
        update(items: [], latestCompleted: nil)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearanceColors()
    }

    private func applyAppearanceColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let showsCompletion = completionPresentation != nil
        let showsRunningState = currentPresentation?.isRunning == true
            && !showsCompletion
            && recordingGuardianState == nil
        if showsRunningState {
            layer?.borderWidth = 1.25
            layer?.borderColor = NSColor.systemBlue
                .withAlphaComponent(isDark ? 0.72 : 0.60).cgColor
            layer?.backgroundColor = NSColor.systemBlue
                .withAlphaComponent(isDark ? 0.22 : 0.14).cgColor
        } else {
            layer?.borderWidth = 0.75
            layer?.borderColor = (isDark ? NSColor.white : NSColor.black)
                .withAlphaComponent(isDark ? (showsCompletion ? 0.24 : 0.32) : (showsCompletion ? 0.10 : 0.16)).cgColor
            layer?.backgroundColor = (isDark ? NSColor.black : NSColor.white)
                .withAlphaComponent(DesktopLiquidGlassTokens.capsuleAlpha(
                    isDark: isDark,
                    showsCompletion: showsCompletion
                )).cgColor
        }
        glassHighlightLayer.colors = showsCompletion
            ? [
                NSColor.white.withAlphaComponent(isDark ? 0.16 : 0.30).cgColor,
                NSColor.white.withAlphaComponent(isDark ? 0.04 : 0.10).cgColor,
                NSColor.clear.cgColor,
            ]
            : showsRunningState ? [
                NSColor.white.withAlphaComponent(isDark ? 0.20 : 0.42).cgColor,
                NSColor.systemBlue.withAlphaComponent(isDark ? 0.18 : 0.24).cgColor,
                NSColor.clear.cgColor,
            ]
            : [
                NSColor.white.withAlphaComponent(0.24).cgColor,
                NSColor.systemBlue.withAlphaComponent(0.08).cgColor,
                NSColor.clear.cgColor,
            ]
        statusLabel.textColor = .labelColor
        detailLabel.textColor = .secondaryLabelColor
    }

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
        let cornerRadius = completionPresentation == nil
            ? bounds.height / 2
            : DesktopFloatingButtonLayout.completionCornerRadius
        layer?.cornerRadius = cornerRadius
        if layer?.mask !== completionShellMaskLayer {
            completionShellMaskLayer.frame = bounds
        }
        glassHighlightLayer.frame = bounds
        ambientLayer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 2, height: bounds.height)
        borderContainerLayer.frame = bounds
        borderMaskLayer.frame = bounds
        borderMaskLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.8, dy: 0.8),
            cornerWidth: cornerRadius - 0.8,
            cornerHeight: cornerRadius - 0.8,
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
        applyAppearanceColors()
        let nextPresentations = DesktopFloatingButtonPresentation.carousel(for: snapshot)
        if let currentPresentation,
           let retainedIndex = nextPresentations.firstIndex(of: currentPresentation) {
            carouselIndex = retainedIndex
        } else {
            carouselIndex = 0
        }
        carouselPresentations = nextPresentations
        guard recordingGuardianState == nil, completionPresentation == nil else { return }
        apply(nextPresentations[carouselIndex], isCarouselAdvance: false)
    }

    func showCompletion(item: WorkItem, result: String?) {
        let presentation = DesktopFloatingButtonPresentation.completion(item: item, result: result)
        [statusHalo.layer, statusLabel.layer, detailLabel.layer]
            .compactMap { $0 }
            .forEach {
                $0.removeAnimation(forKey: "completionContentExit")
                $0.removeAnimation(forKey: "completionOutgoingContentExit")
            }
        completionPresentation = presentation
        statusLabel.wantsLayer = true
        detailLabel.wantsLayer = true
        completionContentAnimationGeneration &+= 1
        let generation = completionContentAnimationGeneration
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            applyCompletionContent(presentation)
            return
        }
        playCompactContentExit { [weak self] in
            guard let self,
                  self.completionContentAnimationGeneration == generation,
                  self.completionPresentation == presentation else { return }
            self.applyCompletionContent(presentation)
            self.playCompletionContentReveal()
        }
    }

    private func applyCompletionContent(_ presentation: DesktopFloatingButtonPresentation) {
        statusLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        normalStatusCenterConstraint?.isActive = false
        completionStatusTopConstraint?.isActive = true
        normalStatusHaloCenterConstraint?.isActive = false
        completionStatusHaloTopConstraint?.isActive = false
        normalStatusHaloCenterConstraint?.isActive = true
        detailLabel.isHidden = false
        applyAppearanceColors()
        needsLayout = true
        apply(presentation, isCarouselAdvance: false)
    }

    func clearCompletion() {
        completionShellAnimationGeneration &+= 1
        completionContentAnimationGeneration &+= 1
        completionShellMaskLayer.removeAllAnimations()
        borderContainerLayer.removeAllAnimations()
        borderGradientLayer.removeAnimation(forKey: "completionMarqueeOrbit")
        borderContainerLayer.opacity = 0
        layer?.mask = nil
        let contentLayers = [statusHalo.layer, statusLabel.layer, detailLabel.layer].compactMap { $0 }
        contentLayers.forEach {
            $0.removeAnimation(forKey: "completionContentReveal")
            $0.removeAnimation(forKey: "completionContentExit")
            $0.removeAnimation(forKey: "completionOutgoingContentExit")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayers.forEach { $0.opacity = 1 }
        CATransaction.commit()
        // Repair stale transition artifacts even when another path already
        // cleared the logical presentation. Otherwise the compact window can
        // survive with its mask or forwards-filled content opacity still at 0.
        guard completionPresentation != nil else {
            statusLabel.wantsLayer = false
            detailLabel.wantsLayer = false
            applyAppearanceColors()
            needsLayout = true
            return
        }
        completionPresentation = nil
        statusLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        completionStatusTopConstraint?.isActive = false
        normalStatusCenterConstraint?.isActive = true
        completionStatusHaloTopConstraint?.isActive = false
        normalStatusHaloCenterConstraint?.isActive = true
        detailLabel.isHidden = true
        detailLabel.stringValue = ""
        statusLabel.wantsLayer = false
        detailLabel.wantsLayer = false
        applyAppearanceColors()
        needsLayout = true
        if recordingGuardianState == nil, !carouselPresentations.isEmpty {
            carouselIndex = min(carouselIndex, carouselPresentations.count - 1)
            apply(carouselPresentations[carouselIndex], isCarouselAdvance: false)
        }
    }

    func updateRecordingGuardian(_ state: VoiceMemoGuardianState?) {
        recordingGuardianState = state
        if state == nil {
            isRecordingStopInProgress = false
        }
        stopRecordingButton.isHidden = state == nil
        normalStatusLabelTrailingConstraint?.isActive = state == nil
        recordingStatusLabelTrailingConstraint?.isActive = state != nil
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

    func updateRecordingStopInProgress(_ isInProgress: Bool) {
        guard recordingGuardianState != nil else { return }
        isRecordingStopInProgress = isInProgress
        stopRecordingButton.isEnabled = !isInProgress
        stopRecordingButton.image = NSImage(
            systemSymbolName: isInProgress ? "hourglass" : "stop.fill",
            accessibilityDescription: isInProgress ? "正在结束录音" : "停止录音"
        )
        stopRecordingButton.contentTintColor = isInProgress ? .secondaryLabelColor : .systemRed
        stopRecordingButton.toolTip = isInProgress ? "正在结束录音…" : "停止录音并保留"
        if isInProgress {
            statusLabel.stringValue = "正在结束…"
            recordingWaveform.update(level: 0, tintColor: .secondaryLabelColor)
        } else if let recordingGuardianState {
            apply(.recordingGuardian(recordingGuardianState), isCarouselAdvance: false)
            recordingWaveform.update(
                level: recordingGuardianState.phase == .silence ? 0 : 0.12,
                tintColor: recordingGuardianState.phase == .silence ? .systemOrange : .systemRed
            )
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

    func isStopRecordingVisibleForTesting() -> Bool {
        !stopRecordingButton.isHidden
    }

    func isRecordingStopInProgressForTesting() -> Bool {
        isRecordingStopInProgress && !stopRecordingButton.isEnabled
    }

    func stopRecordingForTesting() {
        stopRecording()
    }

    private func update(items: [WorkItem], latestCompleted: WorkItem?) {
        applyAppearanceColors()
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
        guard completionPresentation == nil else { return }
        guard carouselPresentations.count > 1 else { return }
        carouselIndex = (carouselIndex + 1) % carouselPresentations.count
        apply(carouselPresentations[carouselIndex], isCarouselAdvance: true)
    }

    func displayedTextForTesting() -> String {
        statusLabel.stringValue
    }

    func displayedDetailForTesting() -> String {
        detailLabel.stringValue
    }

    func isCompletionVisibleForTesting() -> Bool {
        completionPresentation != nil
    }

    func statusLabelHasEnoughWidthForTesting() -> Bool {
        layoutSubtreeIfNeeded()
        return statusLabel.bounds.width >= statusLabel.intrinsicContentSize.width
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
            let fade = CATransition()
            fade.type = .fade
            fade.duration = DesktopFloatingButtonMotion.transitionDuration
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            statusLabel.layer?.add(fade, forKey: "statusTextFade")
        }
        currentTintColor = presentation.tintColor
        applyAppearanceColors()
        statusLabel.stringValue = presentation.displayText
        detailLabel.stringValue = presentation.detailText ?? ""
        statusDot.layer?.backgroundColor = presentation.tintColor.cgColor
        statusDot.layer?.shadowColor = presentation.tintColor.cgColor
        statusDot.layer?.shadowOpacity = 0.55
        statusDot.layer?.shadowRadius = 4
        statusDot.layer?.shadowOffset = .zero
        updatePulse(enabled: presentation.pulses)
        updateRunningChrome(enabled: presentation.isRunning)
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
        opacity.fromValue = 0.62
        opacity.toValue = 1.0
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.94
        scale.toValue = 1.06
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 1.25
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        statusDot.layer?.add(group, forKey: "statusPulse")

        rippleLayer.strokeColor = currentTintColor.withAlphaComponent(0.70).cgColor
        let rippleScale = CABasicAnimation(keyPath: "transform.scale")
        rippleScale.fromValue = 0.72
        rippleScale.toValue = 1.02
        let rippleOpacity = CAKeyframeAnimation(keyPath: "opacity")
        rippleOpacity.values = [0, 0.28, 0]
        rippleOpacity.keyTimes = [0, 0.18, 1]
        let ripple = CAAnimationGroup()
        ripple.animations = [rippleScale, rippleOpacity]
        ripple.duration = 1.8
        ripple.repeatCount = .infinity
        ripple.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(ripple, forKey: "runningRipple")
    }

    private func updateRunningChrome(enabled: Bool) {
        layer?.removeAnimation(forKey: "runningBorderPulse")
        guard enabled,
              completionPresentation == nil,
              recordingGuardianState == nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "borderColor")
        pulse.fromValue = NSColor.systemBlue.withAlphaComponent(0.42).cgColor
        pulse.toValue = NSColor.systemBlue.withAlphaComponent(0.78).cgColor
        pulse.duration = 1.45
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: "runningBorderPulse")
    }

    private func updateAmbientMotion(enabled: Bool, tintColor: NSColor) {
        ambientLayer.removeAnimation(forKey: "ambientDrift")
        borderGradientLayer.removeAnimation(forKey: "borderOrbit")
        ambientLayer.opacity = 0
        if completionPresentation != nil,
           borderGradientLayer.animation(forKey: "completionMarqueeOrbit") != nil {
            return
        }
        borderContainerLayer.opacity = 0
        guard enabled, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        // The status dot already communicates activity. Keeping the capsule
        // surface still makes it feel anchored like a native macOS control.
    }

    private func animateStatusTransition(tintColor: NSColor) {
        let dotPop = CABasicAnimation(keyPath: "transform.scale")
        dotPop.fromValue = 0.86
        dotPop.toValue = 1
        dotPop.duration = DesktopFloatingButtonMotion.transitionDuration
        dotPop.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        statusDot.layer?.add(dotPop, forKey: "statusDotPop")

        rippleLayer.strokeColor = tintColor.withAlphaComponent(0.80).cgColor
        let burstScale = CABasicAnimation(keyPath: "transform.scale")
        burstScale.fromValue = 0.72
        burstScale.toValue = 1.04
        let burstOpacity = CAKeyframeAnimation(keyPath: "opacity")
        burstOpacity.values = [0, 0.42, 0]
        burstOpacity.keyTimes = [0, 0.18, 1]
        let burst = CAAnimationGroup()
        burst.animations = [burstScale, burstOpacity]
        burst.duration = DesktopFloatingButtonMotion.transitionDuration
        burst.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rippleLayer.add(burst, forKey: "statusBurst")

        let borderFlash = CAKeyframeAnimation(keyPath: "borderColor")
        borderFlash.values = [
            NSColor.white.withAlphaComponent(0.14).cgColor,
            tintColor.withAlphaComponent(0.42).cgColor,
            NSColor.white.withAlphaComponent(0.14).cgColor,
        ]
        borderFlash.keyTimes = [0, 0.38, 1]
        borderFlash.duration = DesktopFloatingButtonMotion.transitionDuration
        layer?.add(borderFlash, forKey: "statusBorderFlash")
    }

    private func playCompletionContentReveal() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let beginTime = CACurrentMediaTime() + DesktopFloatingButtonMotion.completionContentDelay
        let contentLayers = [statusHalo.layer, statusLabel.layer, detailLabel.layer].compactMap { $0 }
        for contentLayer in contentLayers {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0
            opacity.toValue = 1
            opacity.beginTime = beginTime
            opacity.duration = DesktopFloatingButtonMotion.completionContentDuration
            opacity.fillMode = .backwards
            opacity.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            contentLayer.add(opacity, forKey: "completionContentReveal")
        }
    }

    private func playCompactContentExit(completion: @escaping () -> Void) {
        let contentLayers = [statusHalo.layer, statusLabel.layer, detailLabel.layer].compactMap { $0 }
        for contentLayer in contentLayers {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0
            opacity.duration = DesktopFloatingButtonMotion.completionContentDuration
            opacity.fillMode = .forwards
            opacity.isRemovedOnCompletion = false
            opacity.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            contentLayer.add(opacity, forKey: "completionOutgoingContentExit")
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopFloatingButtonMotion.completionContentDuration
        ) {
            contentLayers.forEach {
                $0.removeAnimation(forKey: "completionOutgoingContentExit")
            }
            completion()
        }
    }

    func prepareCompletionShellExpansion(from compactSize: NSSize, to expandedSize: NSSize) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        completionShellAnimationGeneration &+= 1
        completionShellMaskLayer.removeAllAnimations()
        configureCompletionShellMask(
            containerSize: expandedSize,
            size: compactSize,
            cornerRadius: compactSize.height / 2
        )
        layer?.mask = completionShellMaskLayer
    }

    func playPreparedCompletionShellExpansion() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let generation = completionShellAnimationGeneration
        layoutSubtreeIfNeeded()
        let finalRect = bounds
        let compactSize = completionShellMaskLayer.bounds.size

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        completionShellMaskLayer.position = CGPoint(x: finalRect.maxX, y: finalRect.maxY)
        completionShellMaskLayer.bounds = NSRect(origin: .zero, size: finalRect.size)
        completionShellMaskLayer.cornerRadius = DesktopFloatingButtonLayout.completionCornerRadius
        CATransaction.commit()

        let boundsMorph = CABasicAnimation(keyPath: "bounds")
        boundsMorph.fromValue = NSRect(origin: .zero, size: compactSize)
        boundsMorph.toValue = NSRect(origin: .zero, size: finalRect.size)
        let morph = CAAnimationGroup()
        morph.animations = [boundsMorph]
        morph.duration = DesktopLiquidMotion.morphDuration
        morph.timingFunction = DesktopLiquidMotion.resizeTiming()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self,
                      self.completionShellAnimationGeneration == generation,
                      self.completionPresentation != nil else { return }
                self.completionShellMaskLayer.removeAllAnimations()
                self.layer?.mask = nil
                self.startCompletionMarquee()
            }
        }
        completionShellMaskLayer.add(morph, forKey: "completionShellMorph")
        CATransaction.commit()
    }

    func playCompletionShellCollapse(
        to compactSize: NSSize,
        completion: @escaping () -> Void
    ) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            completion()
            return
        }
        completionShellAnimationGeneration &+= 1
        fadeCompletionMarqueeForCollapse()
        let generation = completionShellAnimationGeneration
        layoutSubtreeIfNeeded()
        let finalRect = bounds
        let compactRect = DesktopFloatingButtonLayout.completionMorphCompactRect(
            in: finalRect,
            compactSize: compactSize
        )
        configureCompletionShellMask(
            containerSize: finalRect.size,
            size: compactRect.size,
            cornerRadius: compactRect.height / 2
        )
        layer?.mask = completionShellMaskLayer

        let boundsMorph = CABasicAnimation(keyPath: "bounds")
        boundsMorph.fromValue = NSRect(origin: .zero, size: finalRect.size)
        boundsMorph.toValue = NSRect(origin: .zero, size: compactRect.size)
        let morph = CAAnimationGroup()
        morph.animations = [boundsMorph]
        morph.duration = DesktopLiquidMotion.completionMorphCollapseDuration
        morph.timingFunction = DesktopLiquidMotion.resizeTiming()
        playCompletionContentExit()
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                self?.finishCompletionShellCollapse(
                    generation: generation,
                    completion: completion
                )
            }
        }
        completionShellMaskLayer.add(morph, forKey: "completionShellCollapse")
        CATransaction.commit()
        // Core Animation can drop the transaction completion when the app,
        // screen, or layer tree changes during the collapse. The content exit
        // uses a forwards fill, so missing that callback otherwise leaves a
        // permanent empty expanded shell. Finish from the model timeline too;
        // the generation check keeps this idempotent.
        DispatchQueue.main.asyncAfter(
            deadline: .now() + DesktopLiquidMotion.completionMorphCollapseDuration + 0.05
        ) { [weak self] in
            self?.finishCompletionShellCollapse(
                generation: generation,
                completion: completion
            )
        }
    }

    private func finishCompletionShellCollapse(
        generation: UInt,
        completion: @escaping () -> Void
    ) {
        guard completionShellAnimationGeneration == generation,
              completionPresentation != nil else { return }
        completionShellAnimationGeneration &+= 1
        completionShellMaskLayer.removeAllAnimations()
        borderContainerLayer.removeAllAnimations()
        borderGradientLayer.removeAnimation(forKey: "completionMarqueeOrbit")
        borderContainerLayer.opacity = 0
        layer?.mask = nil
        completion()
    }

    func interruptCompletionShellCollapseForTesting() {
        completionShellMaskLayer.removeAnimation(forKey: "completionShellCollapse")
    }

    func compactVisualIsRestoredForTesting() -> Bool {
        layer?.mask == nil
            && [statusHalo.layer, statusLabel.layer].compactMap { $0 }.allSatisfy { $0.opacity == 1 }
    }

    private func startCompletionMarquee() {
        borderContainerLayer.removeAllAnimations()
        borderGradientLayer.removeAnimation(forKey: "completionMarqueeOrbit")

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderContainerLayer.opacity = 0.72
        CATransaction.commit()

        let orbit = CABasicAnimation(keyPath: "transform.rotation.z")
        orbit.fromValue = 0
        orbit.toValue = CGFloat.pi * 2
        orbit.duration = DesktopLiquidMotion.completionMarqueeOrbitDuration
        orbit.repeatCount = .infinity
        orbit.timingFunction = CAMediaTimingFunction(name: .linear)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 0.72
        fadeIn.duration = DesktopLiquidMotion.contentEntranceDuration
        fadeIn.timingFunction = DesktopLiquidMotion.expandTiming()

        borderGradientLayer.add(orbit, forKey: "completionMarqueeOrbit")
        borderContainerLayer.add(fadeIn, forKey: "completionMarqueeFadeIn")
    }

    private func fadeCompletionMarqueeForCollapse() {
        borderContainerLayer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        borderContainerLayer.opacity = 0
        CATransaction.commit()

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.72
        fadeOut.toValue = 0
        fadeOut.duration = DesktopLiquidMotion.completionMorphCollapseDuration
        fadeOut.timingFunction = DesktopLiquidMotion.collapseTiming()
        borderContainerLayer.add(fadeOut, forKey: "completionMarqueeFadeOut")
    }

    func completionMarqueeRepeatsForTesting() -> Bool {
        guard let orbit = borderGradientLayer.animation(forKey: "completionMarqueeOrbit") else {
            return false
        }
        return orbit.repeatCount == .infinity
    }

    func completionMarqueeOpacityForTesting() -> Float {
        borderContainerLayer.opacity
    }

    func startCompletionMarqueeForTesting() {
        startCompletionMarquee()
    }

    private func configureCompletionShellMask(
        containerSize: NSSize,
        size: NSSize,
        cornerRadius: CGFloat
    ) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        completionShellMaskLayer.anchorPoint = CGPoint(x: 1, y: 1)
        completionShellMaskLayer.position = CGPoint(x: containerSize.width, y: containerSize.height)
        completionShellMaskLayer.bounds = NSRect(origin: .zero, size: size)
        completionShellMaskLayer.backgroundColor = NSColor.white.cgColor
        completionShellMaskLayer.cornerRadius = cornerRadius
        completionShellMaskLayer.cornerCurve = .continuous
        completionShellMaskLayer.masksToBounds = true
        CATransaction.commit()
    }

    func completionShellMaskGeometryForTesting() -> (
        position: CGPoint,
        size: CGSize,
        cornerRadius: CGFloat
    ) {
        (
            completionShellMaskLayer.position,
            completionShellMaskLayer.bounds.size,
            completionShellMaskLayer.cornerRadius
        )
    }

    private func playCompletionContentExit() {
        let contentLayers = [statusHalo.layer, statusLabel.layer, detailLabel.layer].compactMap { $0 }
        for contentLayer in contentLayers {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0
            opacity.beginTime = contentLayer.convertTime(CACurrentMediaTime(), from: nil)
                + DesktopLiquidMotion.completionMorphCollapseDuration
                - DesktopFloatingButtonMotion.completionContentExitDuration
            opacity.duration = DesktopFloatingButtonMotion.completionContentExitDuration
            opacity.fillMode = .both
            opacity.isRemovedOnCompletion = false
            opacity.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
            contentLayer.add(opacity, forKey: "completionContentExit")
        }
    }

    func playEntrance() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.94
        scale.toValue = 1
        scale.mass = 1
        scale.stiffness = 380
        scale.damping = 34
        scale.initialVelocity = 0
        scale.duration = DesktopFloatingButtonMotion.entranceDuration
        layer?.add(scale, forKey: "floatingEntranceScale")

        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = -8
        slide.toValue = 0
        slide.duration = DesktopFloatingButtonMotion.entranceDuration
        slide.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        layer?.add(slide, forKey: "floatingEntranceSlide")
    }

    func playExit() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 0.96
        scale.duration = 0.18
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        layer?.add(scale, forKey: "floatingExitScale")
    }

    func motionSnapshot() -> DesktopFloatingButtonMotionSnapshot {
        DesktopFloatingButtonMotionSnapshot(
            root: Set(layer?.animationKeys() ?? []),
            shellMask: Set(completionShellMaskLayer.animationKeys() ?? []),
            statusDot: Set(statusDot.layer?.animationKeys() ?? []),
            statusLabel: Set(statusLabel.layer?.animationKeys() ?? []),
            detailLabel: Set(detailLabel.layer?.animationKeys() ?? []),
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

    private func scheduleHoverActivation() {
        pendingHoverActivation?.cancel()
        pendingHoverActivation = nil
        handleHoverEntered()
    }

    func handleHoverEntered() {
        guard !suppressesHoverActivationUntilExit, recordingGuardianState == nil else { return }
        onHoverEntered?()
    }

    override func mouseExited(with event: NSEvent) {
        pendingHoverActivation?.cancel()
        pendingHoverActivation = nil
        NSCursor.pop()
        setHovering(false)
        suppressesHoverActivationUntilExit = false
    }

    func suppressHoverActivationUntilPointerExit(_ suppress: Bool) {
        suppressesHoverActivationUntilExit = suppress
    }

    func pointerExitForTesting() {
        suppressesHoverActivationUntilExit = false
    }

    override func mouseDown(with event: NSEvent) {
        pendingHoverActivation?.cancel()
        pendingHoverActivation = nil
        setScale(0.96)
    }

    override func mouseUp(with event: NSEvent) {
        setScale(isHovering ? 1.025 : 1)
        handleActivate()
    }

    override func accessibilityPerformPress() -> Bool {
        handleActivate()
        return true
    }

    func handleActivate() {
        onActivate?()
    }

    func hasPendingHoverActivationForTesting() -> Bool {
        pendingHoverActivation != nil && !(pendingHoverActivation?.isCancelled ?? true)
    }

    func scheduleHoverActivationForTesting() {
        scheduleHoverActivation()
    }

    func cancelHoverActivationForTesting() {
        pendingHoverActivation?.cancel()
        pendingHoverActivation = nil
    }

    @objc private func stopRecording() {
        guard !isRecordingStopInProgress else { return }
        updateRecordingStopInProgress(true)
        onStopRecording?()
    }

    private func setHovering(_ hovering: Bool) {
        isHovering = hovering
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DesktopLiquidMotion.hoverDuration
            context.timingFunction = DesktopLiquidMotion.hoverTiming()
            animator().alphaValue = hovering ? 1 : 0.92
        }
        layer?.borderColor = hovering
            ? currentTintColor.withAlphaComponent(0.48).cgColor
            : NSColor.white.withAlphaComponent(0.14).cgColor
        let targetScale: CGFloat = hovering && !DesktopLiquidMotion.reducesMotion
            ? 1.012
            : 1
        setScale(targetScale)
    }

    private func setScale(_ scale: CGFloat) {
        guard let layer else { return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(DesktopLiquidMotion.hoverDuration)
        CATransaction.setAnimationTimingFunction(DesktopLiquidMotion.hoverTiming())
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }
}

@MainActor
final class FloatingDragHandleView: NSView {
    var onDragBegan: (() -> Void)?

    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var isDragging = false
    private var trackingAreaReference: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = DesktopFloatingButtonLayout.dragHandleSize.height / 2
        layer?.cornerCurve = .continuous
        applyAppearance(isHovering: false)
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("移动工作岛")
        toolTip = "拖动移动工作岛"
    }

    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance(isHovering: false)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference { removeTrackingArea(trackingAreaReference) }
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
        NSCursor.openHand.push()
        applyAppearance(isHovering: true)
    }

    override func mouseExited(with event: NSEvent) {
        guard !isDragging else { return }
        NSCursor.pop()
        applyAppearance(isHovering: false)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        isDragging = true
        onDragBegan?()
        NSCursor.closedHand.set()
        applyAppearance(isHovering: true, pressed: true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation,
              let origin = windowOriginAtMouseDown,
              let window else { return }
        let current = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: origin.x + current.x - start.x,
            y: origin.y + current.y - start.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        isDragging = false
        NSCursor.openHand.set()
        applyAppearance(isHovering: bounds.contains(convert(event.locationInWindow, from: nil)))
    }

    func playCompletionExpansion(horizontalTravel: CGFloat, duration: TimeInterval) {
        guard !DesktopLiquidMotion.reducesMotion, let layer else { return }
        layer.removeAnimation(forKey: "completionHandleCollapse")
        let translation = CABasicAnimation(keyPath: "transform.translation.x")
        translation.fromValue = horizontalTravel
        translation.toValue = 0
        translation.duration = duration
        translation.fillMode = .backwards
        translation.timingFunction = DesktopLiquidMotion.resizeTiming()
        layer.add(translation, forKey: "completionHandleExpansion")
    }

    func playCompletionCollapse(horizontalTravel: CGFloat, duration: TimeInterval) {
        guard !DesktopLiquidMotion.reducesMotion, let layer else { return }
        layer.removeAnimation(forKey: "completionHandleExpansion")
        let translation = CABasicAnimation(keyPath: "transform.translation.x")
        translation.fromValue = 0
        translation.toValue = horizontalTravel
        translation.duration = duration
        translation.fillMode = .forwards
        translation.isRemovedOnCompletion = false
        translation.timingFunction = DesktopLiquidMotion.resizeTiming()
        layer.add(translation, forKey: "completionHandleCollapse")
    }

    func finishCompletionTransition() {
        layer?.removeAnimation(forKey: "completionHandleExpansion")
        layer?.removeAnimation(forKey: "completionHandleCollapse")
    }

    var completionMotionKeysForTesting: Set<String> {
        Set(layer?.animationKeys() ?? [])
    }

    private func applyAppearance(isHovering: Bool, pressed: Bool = false) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base = isDark ? NSColor.white : NSColor.black
        layer?.backgroundColor = base.withAlphaComponent(
            DesktopLiquidGlassTokens.dragHandleAlpha(
                isDark: isDark,
                isHovering: isHovering,
                isPressed: pressed
            )
        ).cgColor
        let targetScale: CGFloat = pressed ? 0.92 : (isHovering ? 1.08 : 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(DesktopLiquidMotion.hoverDuration)
        CATransaction.setAnimationTimingFunction(DesktopLiquidMotion.hoverTiming())
        layer?.setAffineTransform(CGAffineTransform(scaleX: targetScale, y: targetScale))
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
        button.font = .systemFont(ofSize: DesktopPanelTypography.sectionFontSize, weight: .semibold)
        button.contentTintColor = .secondaryLabelColor
        button.alignment = .left
        let countLabel = NSTextField(labelWithString: "\(count)")
        countLabel.font = .monospacedDigitSystemFont(
            ofSize: DesktopPanelTypography.sectionFontSize,
            weight: .medium
        )
        countLabel.textColor = .tertiaryLabelColor
        var views: [NSView] = [button, NSView(), countLabel]
        if let actionTitle {
            let actionButton = FirstMouseButton(
                title: actionTitle,
                target: self,
                action: #selector(runAction)
            )
            actionButton.isBordered = false
            actionButton.font = .systemFont(
                ofSize: DesktopPanelTypography.sectionFontSize,
                weight: .medium
            )
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
    private let label = NSTextField(labelWithString: "")
    private var displayedText = ""
    private var displayedPercent: Int?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        label.font = .systemFont(ofSize: DesktopPanelTypography.metadataFontSize, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.alignment = .left
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityIdentifier("额度摘要")
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func update(_ presentation: DesktopQuotaPresentation) {
        guard displayedText != presentation.text
                || displayedPercent != presentation.lowestRemainingPercent else {
            return
        }
        displayedText = presentation.text
        displayedPercent = presentation.lowestRemainingPercent
        label.stringValue = presentation.text

        label.textColor = DesktopQuotaSummaryStyle.textColor(
            lowestRemainingPercent: presentation.lowestRemainingPercent
        )
        setAccessibilityLabel("额度：\(presentation.text)")
    }
}

@MainActor
private final class StatusCapsuleView: NSView {
    private let label = NSTextField(labelWithString: "正在读取…")
    private var currentText = ""
    private var currentColor = NSColor.secondaryLabelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        updateAppearance()
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let displayColor = isDark
            ? currentColor
            : (currentColor.blended(withFraction: 0.28, of: .black) ?? currentColor)
        label.textColor = displayColor
        layer?.borderColor = (isDark ? NSColor.white : displayColor)
            .withAlphaComponent(isDark ? 0.30 : 0.34).cgColor
        layer?.backgroundColor = displayColor
            .withAlphaComponent(DesktopLiquidGlassTokens.statusCapsuleFillAlpha(isDark: isDark))
            .cgColor
    }

    func update(text: String, color: NSColor) {
        guard currentText != text else { return }
        currentText = text
        currentColor = color
        label.stringValue = text
        updateAppearance()
        guard !DesktopLiquidMotion.reducesMotion else { return }
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = layer?.presentation()?.value(forKeyPath: "transform.scale") ?? 0.96
        spring.toValue = 1
        spring.stiffness = 360
        spring.damping = 31
        spring.duration = min(DesktopLiquidMotion.morphDuration, spring.settlingDuration)
        layer?.add(spring, forKey: "capsuleMorph")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer?.presentation()?.opacity ?? 0.72
        fade.toValue = 1
        fade.duration = DesktopLiquidMotion.hoverDuration
        fade.timingFunction = DesktopLiquidMotion.hoverTiming()
        layer?.add(fade, forKey: "capsuleFade")
    }
}

@MainActor
private final class CodexActivityRowView: NSView {
    init(text: String, isCurrent: Bool, isResult: Bool, maximumLineCount: Int) {
        super.init(frame: .zero)

        let marker = NSView()
        marker.wantsLayer = true
        marker.layer?.cornerRadius = 1
        marker.layer?.backgroundColor = (
            isResult ? NSColor.systemGreen : (isCurrent ? .controlAccentColor : .tertiaryLabelColor)
        ).withAlphaComponent(isCurrent || isResult ? 0.9 : 0.55).cgColor
        marker.translatesAutoresizingMaskIntoConstraints = false

        addSubview(marker)
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isCurrent ? 1 : 2),
            marker.topAnchor.constraint(
                equalTo: topAnchor,
                constant: isResult
                    ? DesktopConversationLayout.completedResultMarkerTopInset
                    : (isCurrent ? 2 : 7)
            ),
            marker.widthAnchor.constraint(equalToConstant: isCurrent ? 2 : 4),
            marker.heightAnchor.constraint(equalToConstant: isCurrent || isResult ? 15 : 4),
        ])

        if isResult {
            let textView = NSTextView(frame: .zero)
            textView.textStorage?.setAttributedString(
                DesktopResultTextRenderer.attributedString(for: text)
            )
            textView.drawsBackground = false
            textView.isEditable = false
            textView.isSelectable = true
            textView.textContainerInset = .zero
            textView.textContainer?.lineFragmentPadding = 0
            textView.minSize = .zero
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true

            let scrollView = NSScrollView()
            scrollView.drawsBackground = false
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.horizontalScrollElasticity = .none
            scrollView.autohidesScrollers = true
            scrollView.documentView = textView
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(scrollView)
            NSLayoutConstraint.activate([
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 12.5, weight: .regular)
            label.textColor = isCurrent ? .labelColor : .secondaryLabelColor
            label.alignment = DesktopPanelTypography.activityAlignment
            label.maximumNumberOfLines = maximumLineCount
            label.lineBreakMode = DesktopConversationLayout.activityLineBreakMode
            label.cell?.wraps = true
            label.cell?.usesSingleLineMode = false
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: isCurrent ? 10 : 12),
                label.trailingAnchor.constraint(equalTo: trailingAnchor),
                label.topAnchor.constraint(equalTo: topAnchor),
                label.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class WorkItemRowView: NSView, NSTextFieldDelegate {
    var onSelected: (() -> Void)?
    var onDetailsSelected: (() -> Void)?
    var onPromptSubmitted: ((CodexPrompt) -> Void)?
    var onCodexTransferSelected: (() -> Void)? {
        didSet {
            codexTransferButton.isHidden = onCodexTransferSelected == nil
                || showsPersistentPrimaryAction
        }
    }
    var onAcknowledgeSelected: (() -> Void)? {
        didSet { acknowledgeButton.isHidden = onAcknowledgeSelected == nil }
    }
    var onOutputSelected: (() -> Void)? {
        didSet { outputButton.isHidden = onOutputSelected == nil }
    }

    private let actions = NSStackView()
    private let primaryActionButton = FirstMouseButton()
    private let outputButton = FirstMouseButton()
    private let codexTransferButton = FirstMouseButton()
    private let acknowledgeButton = FirstMouseButton()
    private let conversationInputBackground = RoundedInputBackground()
    private let promptField = PastedImageTextField(string: "")
    private let imageCountLabel = NSTextField(labelWithString: "")
    private let sendButton = FirstMouseButton()
    private let activityTimeline = NSStackView()
    private weak var mainRowForTesting: NSStackView?
    private weak var titleForTesting: NSTextField?
    private weak var resultScrollViewForTesting: NSScrollView?
    private let glassHighlightLayer = CAGradientLayer()
    private var tracking: NSTrackingArea?
    private var isHovering = false
    private let opensThreadWhenPromptIsEmpty: Bool
    private let contentMode: DesktopContentMode
    private let showsPersistentPrimaryAction: Bool
    private let cardHeight: CGFloat
    var requiredHeight: CGFloat { cardHeight }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: cardHeight)
    }

    init(
        item: WorkItem,
        lastAssistantResult: String? = nil,
        contentMode: DesktopContentMode = .clean,
        measurementWidth: CGFloat = DesktopConversationLayout.defaultMeasurementWidth
    ) {
        self.contentMode = contentMode
        cardHeight = DesktopConversationLayout.cardHeight(
            item: item,
            lastAssistantResult: lastAssistantResult,
            contentMode: contentMode,
            measurementWidth: measurementWidth
        )
        opensThreadWhenPromptIsEmpty = CodexCardPrimaryActionPolicy
            .opensThreadWhenPromptIsEmpty(status: item.status)
        showsPersistentPrimaryAction = WorkItemCardActionPolicy
            .showsPersistentPrimaryAction(status: item.status)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0.5
        glassHighlightLayer.startPoint = CGPoint(x: 0.1, y: 1)
        glassHighlightLayer.endPoint = CGPoint(x: 0.88, y: 0)
        layer?.addSublayer(glassHighlightLayer)
        updateAppearance()
        layer?.masksToBounds = true

        let indicator = NSView()
        indicator.wantsLayer = true
        indicator.layer?.backgroundColor = item.status.color.cgColor
        indicator.layer?.cornerRadius = 3
        indicator.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            indicator.widthAnchor.constraint(equalToConstant: 6),
            indicator.heightAnchor.constraint(equalToConstant: 6),
        ])

        let title = NSTextField(labelWithString: item.displayTitle)
        titleForTesting = title
        title.font = .systemFont(ofSize: 13.5, weight: .regular)
        title.alignment = DesktopPanelTypography.metadataAlignment
        // Titles are navigation labels, not body copy. Keep every card header on
        // one line so a narrow panel cannot turn short titles into tall blocks.
        title.lineBreakMode = .byTruncatingTail
        title.maximumNumberOfLines = DesktopConversationLayout.titleLineLimit
        title.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )

        let detail = NSTextField(labelWithString: item.displayDetail)
        detail.font = .systemFont(ofSize: DesktopPanelTypography.metadataFontSize, weight: .regular)
        detail.alignment = DesktopPanelTypography.metadataAlignment
        detail.textColor = .tertiaryLabelColor
        detail.lineBreakMode = .byTruncatingMiddle
        detail.maximumNumberOfLines = 1
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [title, detail])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        textStack.setHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(
            .defaultLow,
            for: .horizontal
        )
        title.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true
        detail.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true

        // The card is visually one click target, but AppKit label/stack views
        // consume mouse events instead of bubbling them to WorkItemRowView.
        // Route every non-interactive part through the same selection action.
        [indicator, textStack].forEach {
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

        [codexTransferButton, acknowledgeButton, outputButton, detailsButton].forEach {
            configureIconActionButton($0)
        }
        actions.setViews(
            [codexTransferButton, acknowledgeButton, outputButton, detailsButton],
            in: .leading
        )
        actions.orientation = .horizontal
        actions.spacing = 2
        actions.alphaValue = 0
        actions.isHidden = true
        actions.setHuggingPriority(.required, for: .horizontal)
        actions.setContentCompressionResistancePriority(.required, for: .horizontal)

        primaryActionButton.title = "继续处理"
        primaryActionButton.font = .systemFont(ofSize: 12.5, weight: .semibold)
        primaryActionButton.bezelStyle = .rounded
        primaryActionButton.controlSize = .regular
        primaryActionButton.contentTintColor = .controlAccentColor
        primaryActionButton.target = self
        primaryActionButton.action = #selector(selectRow)
        primaryActionButton.toolTip = "查看结果并继续处理"
        primaryActionButton.setAccessibilityLabel("查看结果并继续处理")
        primaryActionButton.isHidden = !showsPersistentPrimaryAction
        primaryActionButton.setContentHuggingPriority(.required, for: .horizontal)
        primaryActionButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            primaryActionButton.heightAnchor.constraint(
                equalToConstant: WorkItemCardActionLayout.primaryHeight
            ),
            primaryActionButton.widthAnchor.constraint(
                equalToConstant: WorkItemCardActionLayout.primaryMinimumWidth
            ),
        ])

        // `textStack` is the flexible element. A separate spacer here would
        // consume the remaining width and truncate even short titles early.
        let mainRow = NSStackView(views: [indicator, textStack, primaryActionButton, actions])
        mainRowForTesting = mainRow
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.distribution = .fill
        mainRow.spacing = 7
        mainRow.heightAnchor.constraint(
            equalToConstant: DesktopConversationLayout.titleHeaderHeight(
                for: item.displayTitle,
                width: measurementWidth
            )
        ).isActive = true
        mainRow.setContentCompressionResistancePriority(.required, for: .vertical)
        textStack.setContentCompressionResistancePriority(.required, for: .vertical)
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        detail.setContentCompressionResistancePriority(.required, for: .vertical)
        mainRow.translatesAutoresizingMaskIntoConstraints = false

        if item.id.hasPrefix("codex:") {
            let summary = DesktopConversationLayout.summary(
                item: item,
                lastAssistantResult: lastAssistantResult,
                contentMode: contentMode
            )
            activityTimeline.orientation = .vertical
            activityTimeline.alignment = .leading
            activityTimeline.spacing = 6
            activityTimeline.setHuggingPriority(.required, for: .vertical)
            activityTimeline.setContentCompressionResistancePriority(.required, for: .vertical)
            for (index, entry) in summary.entries.enumerated() {
                let isCurrent = item.status == .running && index == summary.entries.count - 1
                let row = CodexActivityRowView(
                    text: entry,
                    isCurrent: isCurrent,
                    isResult: item.status != .running,
                    maximumLineCount: item.status == .running
                        ? (isCurrent
                            ? DesktopConversationLayout.currentActivityLineLimit
                            : DesktopConversationLayout.historicalActivityLineLimit)
                        : DesktopConversationLayout.completedResultLineLimit
                )
                activityTimeline.addArrangedSubview(row)
                if item.status != .running {
                    resultScrollViewForTesting = row.subviews.compactMap { $0 as? NSScrollView }.first
                }
                row.widthAnchor.constraint(equalTo: activityTimeline.widthAnchor).isActive = true
                row.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(selectRow)))
            }
            promptField.placeholderString = "直接回复…"
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
                accessibilityDescription: "发送回复"
            )
            sendButton.isBordered = false
            sendButton.contentTintColor = .controlAccentColor
            sendButton.target = self
            sendButton.action = #selector(submitPrompt)
            sendButton.toolTip = opensThreadWhenPromptIsEmpty
                ? "打开 Codex；输入内容后发送"
                : "发送回复"

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

            var conversationViews: [NSView] = [mainRow, activityTimeline]
            if let count = item.phaseCount, count > 0 {
                let progress = StageProgressView(
                    count: count,
                    current: min(max(item.phaseIndex ?? 0, 0), count),
                    color: item.status.color
                )
                progress.setContentHuggingPriority(.defaultLow, for: .horizontal)
                let progressLabel = NSTextField(labelWithString: summary.progressText ?? "")
                progressLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
                progressLabel.textColor = .tertiaryLabelColor
                progressLabel.setContentHuggingPriority(.required, for: .horizontal)
                let progressRow = NSStackView(views: [progress, progressLabel])
                progressRow.orientation = .horizontal
                progressRow.alignment = .centerY
                progressRow.spacing = 8
                progressRow.heightAnchor.constraint(equalToConstant: 13).isActive = true
                conversationViews.append(progressRow)
            }
            conversationViews.append(conversationInputBackground)
            let stack = NSStackView(views: conversationViews)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 0
            stack.setCustomSpacing(item.status == .running ? 4 : 2, after: mainRow)
            stack.setCustomSpacing(
                item.status == .running ? (item.phaseCount == nil ? 10 : 7) : 5,
                after: activityTimeline
            )
            if conversationViews.count > 3 {
                stack.setCustomSpacing(8, after: conversationViews[2])
            }
            stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.setHuggingPriority(.required, for: .vertical)
            stack.setContentCompressionResistancePriority(.required, for: .vertical)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            conversationViews.forEach {
                $0.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(
                    equalTo: leadingAnchor,
                    constant: DesktopPanelLayout.workItemHorizontalInset
                ),
                stack.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -DesktopPanelLayout.workItemHorizontalInset
                ),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: item.status == .running ? 5 : 3),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: item.status == .running ? -5 : -3),
            ])
        } else {
            addSubview(mainRow)
            NSLayoutConstraint.activate([
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func layout() {
        super.layout()
        glassHighlightLayer.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var activityRowsFillLeadingEdgeForTesting: Bool {
        layoutSubtreeIfNeeded()
        activityTimeline.layoutSubtreeIfNeeded()
        guard !activityTimeline.arrangedSubviews.isEmpty else { return false }
        return activityTimeline.arrangedSubviews.allSatisfy { row in
            abs(row.frame.minX) < 0.5
                && abs(row.frame.width - activityTimeline.bounds.width) < 0.5
        }
    }


    var contentStaysInsideCardForTesting: Bool {
        layoutSubtreeIfNeeded()
        activityTimeline.layoutSubtreeIfNeeded()
        // NSTextField's cell draws up to 2pt beyond its alignment rect.
        let tolerance: CGFloat = 2.1
        guard let titleForTesting,
              titleForTesting.frame.minX >= -tolerance,
              titleForTesting.frame.maxX <= titleForTesting.superview!.bounds.maxX + tolerance
        else { return false }
        guard let resultScrollViewForTesting else { return true }
        resultScrollViewForTesting.layoutSubtreeIfNeeded()
        guard !resultScrollViewForTesting.hasHorizontalScroller,
              let textView = resultScrollViewForTesting.documentView as? NSTextView
        else { return false }
        return textView.frame.width <= resultScrollViewForTesting.contentSize.width + tolerance
    }

    var titleUsesAvailableHeaderWidthForTesting: Bool {
        layoutSubtreeIfNeeded()
        guard showsPersistentPrimaryAction,
              !primaryActionButton.isHidden,
              let mainRowForTesting,
              let titleForTesting,
              let titleStack = titleForTesting.superview
        else { return true }
        let titleFrame = convert(titleForTesting.frame, from: titleStack)
        let actionFrame = convert(primaryActionButton.frame, from: primaryActionButton.superview)
        let rowFrame = convert(mainRowForTesting.bounds, from: mainRowForTesting)
        return actionFrame.minX - titleFrame.maxX <= 8
            && rowFrame.maxX - actionFrame.maxX <= 1
            && abs(actionFrame.width - WorkItemCardActionLayout.primaryMinimumWidth) <= 0.5
    }

    var headerUsesFullWidthForTesting: Bool {
        layoutSubtreeIfNeeded()
        guard let mainRowForTesting,
              let titleForTesting,
              let titleStack = titleForTesting.superview
        else { return false }
        let titleFrame = convert(titleForTesting.frame, from: titleStack)
        let trailingView = !actions.isHidden
            ? actions
            : (!primaryActionButton.isHidden ? primaryActionButton : titleStack)
        let trailingFrame = convert(trailingView.frame, from: trailingView.superview)
        let rowFrame = convert(mainRowForTesting.bounds, from: mainRowForTesting)
        return trailingFrame.minX - titleFrame.maxX <= 8
            && rowFrame.maxX - trailingFrame.maxX <= 1
    }

    func setHoveringForTesting(_ hovering: Bool) {
        setHovering(hovering)
    }

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
        activityTimeline.arrangedSubviews.forEach { view in
            activityTimeline.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let row = CodexActivityRowView(
            text: text,
            isCurrent: isBusy,
            isResult: !isBusy,
            maximumLineCount: isBusy ? 2 : DesktopConversationLayout.completedResultLineLimit
        )
        activityTimeline.addArrangedSubview(row)
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
            Task { @MainActor [weak self] in
                guard let self, !isHovering else { return }
                actions.isHidden = true
            }
        }
        updateAppearance()
    }

    private func updateAppearance() {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        glassHighlightLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.12 : 0.34).cgColor,
            NSColor.white.withAlphaComponent(isDark ? 0.035 : 0.10).cgColor,
            NSColor.clear.cgColor,
        ]
        glassHighlightLayer.locations = [0, 0.38, 1]
        layer?.borderColor = (isHovering ? NSColor.controlAccentColor : DesktopPanelPalette.stroke)
            .withAlphaComponent(isHovering ? 0.58 : (isDark ? 0.55 : 0.42))
            .cgColor(resolvedFor: effectiveAppearance)
        layer?.backgroundColor = (isHovering ? DesktopPanelPalette.hoveredCard : DesktopPanelPalette.card)
            .withAlphaComponent(DesktopLiquidGlassTokens.cardAlpha(
                isDark: isDark,
                isHovering: isHovering
            ))
            .cgColor(resolvedFor: effectiveAppearance)
    }

    private func actionButton(symbol: String, toolTip: String) -> NSButton {
        let button = FirstMouseButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip)
        button.isBordered = false
        button.toolTip = toolTip
        return button
    }

    private func configureIconActionButton(_ button: NSButton) {
        button.image = button.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(
                pointSize: WorkItemCardActionLayout.iconPointSize,
                weight: .medium
            )
        )
        button.imagePosition = .imageOnly
        button.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: WorkItemCardActionLayout.iconHitSize),
            button.heightAnchor.constraint(equalToConstant: WorkItemCardActionLayout.iconHitSize),
        ])
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

    override func mouseDown(with event: NSEvent) {
        // The dashboard is an accessory app and is commonly opened while another
        // app remains active. A first-mouse click can focus the field editor
        // visually without moving the active input context to this process, so
        // direct keys work while Chinese IME marked text never arrives. Activate
        // before AppKit creates the field editor and dispatches the click.
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        window?.makeKey()
        super.mouseDown(with: event)
    }

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
        if isPaste {
            guard isActivePasteTarget else { return false }
            if pasteTextFromGeneralPasteboard() { return true }
            if let image = NSImage(pasteboard: .general), let url = Self.writeTemporaryPNG(image) {
                imageURLs.append(url)
                onImagesChanged?(imageURLs.count)
                return true
            }
        }
        let isDelete = modifiers.isEmpty && (event.keyCode == 51 || event.characters == "\u{7f}")
        if isDelete, stringValue.isEmpty, let url = imageURLs.popLast() {
            try? FileManager.default.removeItem(at: url)
            onImagesChanged?(imageURLs.count)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private var isActivePasteTarget: Bool {
        // Key equivalents are offered to multiple sibling views. Without an
        // explicit focus check, the first conversation field in view order can
        // consume Command-V even while the new-task field owns the insertion
        // point. A detached field is allowed for focused unit-level behavior.
        guard let window else { return true }
        let responder = window.firstResponder
        return responder === self || responder === currentEditor()
    }

    @discardableResult
    private func pasteTextFromGeneralPasteboard() -> Bool {
        guard let text = NSPasteboard.general.string(forType: .string) else { return false }
        if let editor = currentEditor() as? NSTextView {
            editor.insertText(text, replacementRange: editor.selectedRange())
        } else {
            stringValue += text
        }
        return true
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
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        highlightLayer.colors = [
            (isDark ? NSColor.white : NSColor.black)
                .withAlphaComponent(isDark ? 0.06 : 0.018).cgColor,
            accent.withAlphaComponent(isFocused ? 0.10 : 0.025).cgColor,
            NSColor.clear.cgColor,
        ]
        layer?.backgroundColor = DesktopPanelPalette.input
            .withAlphaComponent(DesktopLiquidGlassTokens.inputAlpha(isDark: isDark))
            .cgColor(resolvedFor: effectiveAppearance)
        layer?.borderWidth = isFocused ? 1.1 : 0.7
        layer?.borderColor = (isFocused ? accent : DesktopPanelPalette.stroke)
            .withAlphaComponent(isFocused ? 0.78 : (isDark ? 0.60 : 0.48))
            .cgColor(resolvedFor: effectiveAppearance)
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
final class PanelBackgroundView: NSVisualEffectView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingAreaReference: NSTrackingArea?
    private let surfaceHighlightLayer = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 22
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        surfaceHighlightLayer.startPoint = CGPoint(x: 0.05, y: 1)
        surfaceHighlightLayer.endPoint = CGPoint(x: 0.95, y: 0)
        // The window itself tracks a live resize frame by frame. Core Animation's
        // default geometry interpolation makes this decorative layer trail the
        // window by roughly 250 ms, producing the tiled background seen while
        // dragging the resize handle.
        surfaceHighlightLayer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
        ]
        layer?.addSublayer(surfaceHighlightLayer)
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceHighlightLayer.frame = bounds
        CATransaction.commit()
    }

    var surfaceHighlightFrameForTesting: CGRect { surfaceHighlightLayer.frame }
    var surfaceHighlightAnimationKeysForTesting: [String] {
        surfaceHighlightLayer.animationKeys() ?? []
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
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        material = isDark ? .hudWindow : .popover
        surfaceHighlightLayer.colors = [
            NSColor.white.withAlphaComponent(isDark ? 0.12 : 0.42).cgColor,
            NSColor.white.withAlphaComponent(isDark ? 0.04 : 0.09).cgColor,
            NSColor.clear.cgColor,
        ]
        surfaceHighlightLayer.locations = [0, 0.48, 1]
        layer?.backgroundColor = DesktopPanelPalette.base
            .withAlphaComponent(DesktopLiquidGlassTokens.panelBaseAlpha(isDark: isDark))
            .cgColor(resolvedFor: effectiveAppearance)
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white
            .withAlphaComponent(isDark ? 0.24 : 0.48)
            .cgColor(resolvedFor: effectiveAppearance)
        layer?.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.34 : 0.18).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 20
        layer?.shadowOffset = CGSize(width: 0, height: -2)
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
