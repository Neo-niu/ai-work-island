import AppKit
@testable import CodexTouchBar
import CodexTouchBarCore
import Testing

@Test func completionUIReviewModeRequiresAnExplicitLaunchArgument() {
    #expect(DesktopCompletionUIReviewMode(arguments: ["AI工作岛"]) == .disabled)
    #expect(DesktopCompletionUIReviewMode(
        arguments: ["AI工作岛", "--ui-review-completion"]
    ) == .looping)
    #expect(DesktopCompletionUIReviewMode(
        arguments: ["AI工作岛", "--ui-review-completion-hold"]
    ) == .held)
    #expect(DesktopCompletionUIReviewMode(
        arguments: ["AI工作岛", "--ui-review-completion", "--ui-review-completion-hold"]
    ) == .held)
}

@MainActor
@Test func heldCompletionUIReviewUsesTheExpandedCapsuleWithoutARealTask() {
    let controller = DesktopStatusPanelController()

    controller.startCompletionUIReview(.held)

    let now = Date()
    controller.update(snapshot: WorkStatusSnapshot(items: [
        WorkItem(id: "codex:real", source: "Codex", title: "真实任务", status: .running, updatedAt: now)
    ], automationIssues: [], refreshedAt: now))
    controller.update(snapshot: WorkStatusSnapshot(items: [
        WorkItem(id: "codex:real", source: "Codex", title: "真实任务", status: .completed, updatedAt: now)
    ], automationIssues: [], refreshedAt: now))
    controller.activateFloatingButtonForTesting()

    #expect(controller.floatingPanelIsVisibleForTesting)
    #expect(!controller.panelIsVisibleForTesting)
    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.completionCanvasSize)
    #expect(controller.floatingButtonMotionForTesting.shellMask.contains("completionShellMorph"))
    #expect(!controller.completionCollapseIsScheduledForTesting)
    controller.orderWindowsOutForTesting()
}

@MainActor
@Test func imageRendererCombinesAnIconAndTitleIntoOneDrawableImage() {
    let image = TouchBarImageRenderer.image(
        title: "Effort",
        symbolName: "brain.head.profile"
    )

    #expect(image.size.width > 45)
    #expect(image.size.height >= 16)
    #expect(!image.isTemplate)
}

@MainActor
@Test func imageRendererCanDrawATextOnlyOption() {
    let image = TouchBarImageRenderer.image(title: "Ultra")

    #expect(image.size.width > 20)
    #expect(image.size.height >= 16)
}

@MainActor
@Test func imageRendererDrawsTheWeeklyLimitWithAnIcon() {
    let image = TouchBarImageRenderer.image(
        title: "%94 kaldı",
        symbolName: "calendar"
    )

    #expect(image.size.width > 70)
    #expect(image.size.height >= 16)
}

@MainActor
@Test func unreadProjectKeepsWhiteContentAndUsesOnlyAPurpleDot() {
    let presentation = ProjectScrubberItemView.presentation(
        title: "aviaCore",
        count: 2,
        hasUnread: true,
        isSelected: false,
        isPlaceholder: false
    )

    #expect(presentation.title == "aviaCore · 2")
    #expect(presentation.textColor == .white)
    #expect(presentation.trailingDotColor == .systemPurple)
}

@MainActor
@Test func selectedProjectDoesNotAddAnArrowOrYellowText() {
    let presentation = ProjectScrubberItemView.presentation(
        title: "codex_touchbar",
        count: 1,
        hasUnread: false,
        isSelected: true,
        isPlaceholder: false
    )

    #expect(presentation.title == "codex_touchbar")
    #expect(presentation.textColor == .white)
    #expect(presentation.trailingDotColor == nil)
}

@MainActor
@Test func selectedProjectUsesAnExplicitPersistentRoundedBackground() {
    let presentation = ProjectScrubberItemView.presentation(
        title: "codex_touchbar",
        count: 1,
        hasUnread: false,
        isSelected: true,
        isPlaceholder: false
    )

    #expect(presentation.backgroundColor == TouchBarControlStyle.backgroundColor)
    #expect(presentation.cornerRadius == TouchBarControlStyle.cornerRadius)
}

@MainActor
@Test func projectNavigationButtonUsesVisibleContentAndAnExplicitBackground() {
    let button = TouchBarControlStyle.makeNavigationButton(
        symbolName: "chevron.forward",
        accessibilityLabel: "Expand projects",
        target: nil,
        action: nil
    )

    #expect(button.image?.isTemplate == false)
    #expect(!button.isBordered)
    #expect(button.layer?.backgroundColor == TouchBarControlStyle.backgroundColor.cgColor)
    #expect(button.layer?.cornerRadius == TouchBarControlStyle.cornerRadius)
}

@MainActor
@Test func trailingDotAddsIndependentIndicatorWidth() {
    let plain = TouchBarImageRenderer.image(title: "Project")
    let unread = TouchBarImageRenderer.image(
        title: "Project",
        trailingDotColor: .systemPurple
    )

    #expect(unread.size.width > plain.size.width)
    #expect(unread.size.height == plain.size.height)
}

@MainActor
@Test func dashboardQuotaRingsUseCompactTouchBarSizing() {
    let quota = QuotaRingView()
    quota.frame.size = NSSize(width: 112, height: 30)
    quota.update(title: "周", remainingPercent: 58)
    quota.layoutSubtreeIfNeeded()
    #expect(quota.fittingSize.width == 112)
    #expect(quota.fittingSize.height == 30)
    #expect(quota.accessibilityLabel() == "周额度剩余 58%")

    let shapeLayers = quota.layer?.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
    #expect(shapeLayers.count == 2)
    for shapeLayer in shapeLayers {
        #expect(shapeLayer.affineTransform().isIdentity)
        #expect(shapeLayer.frame == quota.bounds)
        #expect(shapeLayer.path?.boundingBoxOfPath == CGRect(x: 7, y: 3, width: 24, height: 24))
    }

    quota.update(
        title: "Codex",
        remainingPercent: 58,
        detail: "5时 71% · 周 58%",
        accessibilityText: "5小时额度剩余 71%，周额度剩余 58%"
    )
    #expect(quota.accessibilityLabel() == "5小时额度剩余 71%，周额度剩余 58%")

    quota.update(title: "公司", remainingPercent: nil)
    #expect(quota.accessibilityLabel() == "公司额度不可用")

}

@Test func desktopPanelWidthDoesNotDependOnTaskCount() {
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 0).width == 480)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 0).height == 205)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 1).width == 480)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 7).width == 480)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 7).height == 587)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 7, sectionCount: 4).height == 675)
}

@Test func desktopPanelPrioritizesLiveWorkBeforeCreationAndQuota() {
    #expect(DesktopPanelLayout.sectionOrder == [
        .header, .tasks, .newTask, .quota, .footer,
    ])
}

@Test func activityTypographyUsesOneLeftReadingEdgeAndLegibleMetadata() {
    #expect(DesktopPanelTypography.activityAlignment == .left)
    #expect(DesktopPanelTypography.metadataAlignment == .left)
    #expect(DesktopPanelTypography.metadataFontSize >= 11)
    #expect(DesktopPanelTypography.sectionFontSize >= 11)
}

@MainActor
@Test func runningActivityRowsFillTheCardFromTheLeadingEdge() {
    let controller = DesktopStatusPanelController()
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:alignment",
            source: "Codex",
            title: "对齐测试",
            detail: "任务",
            status: .running,
            updatedAt: Date(),
            activities: ["运行命令", "修改文件"]
        )],
        automationIssues: []
    ))

    #expect(controller.activityRowsFillLeadingEdgeForTesting)
    controller.hide()
}

@MainActor
@Test func longURLsAndCompletedTextStayInsideTheConversationCard() {
    let controller = DesktopStatusPanelController()
    let itemID = "codex:right-edge"
    controller.setCodexResultForTesting(
        "需要注意：仅从当前看板 SQL 可以确认目标来自 Barley 维表；"
            + String(repeating: "https://barley.rush.zhenguanyu.com/dashboard", count: 5),
        itemID: itemID
    )
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: itemID,
            source: "Codex",
            title: "帮我看下这个barley看板的数据源，目标来自哪，实际课次来自哪 "
                + String(repeating: "https://barley.rush.zhenguanyu.com/dashboard", count: 3),
            status: .waiting,
            updatedAt: Date()
        )],
        automationIssues: []
    ))

    #expect(controller.conversationRowsStayInsideCardForTesting)
    controller.hide()
}

@MainActor
@Test func waitingTitleUsesRemainingSpaceWithoutStretchingPrimaryAction() {
    let controller = DesktopStatusPanelController()
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:available-title-width",
            source: "Codex",
            title: "修复工作岛展开面板标题",
            status: .waiting,
            updatedAt: Date()
        )],
        automationIssues: []
    ))

    #expect(controller.conversationTitlesUseAvailableHeaderWidthForTesting)
    controller.hide()
}

@MainActor
@Test func runningTitleAndHoverActionsUseTheFullHeaderWidth() {
    let controller = DesktopStatusPanelController()
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:hover-title-width",
            source: "Codex",
            title: "今天的数据合并播报没完成",
            detail: "自动下载数据并合并",
            status: .running,
            updatedAt: Date(),
            activities: ["已连接 Codex，正在等待首条进度"]
        )],
        automationIssues: []
    ))

    #expect(controller.conversationHoveredHeadersUseFullWidthForTesting)
    controller.hide()
}

@Test func quotaPresentationCollapsesBothSourcesIntoOneLowPriorityLine() {
    let recordedAt = Date(timeIntervalSince1970: 100)
    let presentation = DesktopQuotaPresentation.make(snapshot: WorkStatusSnapshot(
        items: [],
        automationIssues: [],
        codexShortTermLimit: WeeklyLimitUsage(
            usedPercent: 29,
            resetsAt: nil,
            recordedAt: recordedAt
        ),
        codexWeeklyLimit: WeeklyLimitUsage(
            usedPercent: 90,
            resetsAt: nil,
            recordedAt: recordedAt
        ),
        companyQuota: CompanyModelQuota(totalUSD: 200, usedUSD: 28, resetsAt: nil)
    ))

    #expect(presentation.text == "公司 86% · Codex 5小时 71% / 本周 10%")
    #expect(presentation.lowestRemainingPercent == 10)
}

@Test func desktopQuotaSummaryKeepsCriticalColorSubdued() {
    let critical = DesktopQuotaSummaryStyle.textColor(lowestRemainingPercent: 10)
    let warning = DesktopQuotaSummaryStyle.textColor(lowestRemainingPercent: 35)
    let healthy = DesktopQuotaSummaryStyle.textColor(lowestRemainingPercent: 70)

    #expect(critical.alphaComponent == 0.68)
    #expect(warning.alphaComponent == 0.78)
    #expect(healthy == .tertiaryLabelColor)
}

@Test func attentionCardsKeepOnePrimaryActionVisible() {
    #expect(WorkItemCardActionPolicy.showsPersistentPrimaryAction(status: .waiting))
    #expect(WorkItemCardActionPolicy.showsPersistentPrimaryAction(status: .failed))
    #expect(WorkItemCardActionPolicy.showsPersistentPrimaryAction(status: .stale))
    #expect(!WorkItemCardActionPolicy.showsPersistentPrimaryAction(status: .running))
    #expect(!WorkItemCardActionPolicy.showsPersistentPrimaryAction(status: .completed))
}

@Test func taskCardActionsHaveComfortableTargets() {
    #expect(WorkItemCardActionLayout.primaryHeight == 28)
    #expect(WorkItemCardActionLayout.primaryMinimumWidth == 76)
    #expect(WorkItemCardActionLayout.iconHitSize == 28)
    #expect(WorkItemCardActionLayout.iconPointSize == 15)
}

@Test func conversationCardUsesTheAvailablePanelWidth() {
    #expect(DesktopPanelLayout.contentWidth == 448)
    #expect(DesktopPanelLayout.conversationContentWidth == 426)
}

@Test func cleanConversationCardUsesCompactFallbackHeight() {
    let withoutConversation = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1
    )
    let withConversation = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1,
        conversationItemCount: 1
    )

    #expect(withConversation.height - withoutConversation.height == 84)
}

@Test func detailedModeReservesReadableFallbackHeight() {
    let withoutConversation = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1,
        contentMode: .detailed
    )
    let withConversation = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1,
        conversationItemCount: 1,
        contentMode: .detailed
    )

    #expect(DesktopContentMode.clean.title == "精简 · 最近 4 条进度")
    #expect(DesktopContentMode.detailed.title == "详细 · 最近 6 条进度")
    #expect(DesktopContentMode.detailed.maximumActivityCount == 6)
    #expect(withConversation.height - withoutConversation.height == 104)
}

@Test func contentDensityModesBoundActivityCountAndPanelHeight() {
    #expect(DesktopContentMode.clean.maximumActivityCount == 4)
    #expect(DesktopContentMode.clean.conversationStatusFontSize == 11)
    #expect(DesktopContentMode.detailed.maximumActivityCount == 6)
    #expect(DesktopContentMode.detailed.conversationStatusFontSize == 11.5)
    #expect(DesktopContentMode.detailed.conversationStatusTextColor(isBusy: false) == .labelColor)
    #expect(DesktopContentMode.detailed.conversationStatusTextColor(isBusy: true) == .labelColor)
    #expect(DesktopContentMode.clean.conversationStatusTextColor(isBusy: false) == .secondaryLabelColor)
    #expect(DesktopContentMode.clean.conversationStatusTextColor(isBusy: true) == .controlAccentColor)

    #expect(DesktopPanelLayout.contentSize(
        visibleItemCount: 7,
        sectionCount: 4,
        conversationItemCount: 7,
        contentMode: .clean
    ).height == 720)
    #expect(DesktopPanelLayout.contentSize(
        visibleItemCount: 7,
        sectionCount: 4,
        conversationItemCount: 7,
        contentMode: .detailed
    ).height == 746)
}

@Test func conversationCardHeightAdaptsToVisibleOutput() {
    #expect(DesktopConversationLayout.activityLineBreakMode == .byWordWrapping)
    #expect(DesktopConversationLayout.historicalActivityLineLimit == 1)
    #expect(DesktopConversationLayout.currentActivityLineLimit == 2)

    let completedAutomation = WorkItem(
        id: "automation:visual-review",
        source: "自动化",
        title: "完成任务",
        status: .completed,
        updatedAt: Date(),
        phase: "全部完成",
        phaseIndex: 3,
        phaseCount: 3
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: completedAutomation,
        lastAssistantResult: nil,
        contentMode: .detailed
    ) == 56)
    #expect(DesktopConversationLayout.extraHeight(
        item: completedAutomation,
        lastAssistantResult: nil,
        contentMode: .detailed
    ) == 0)

    let running = WorkItem(
        id: "codex:adaptive",
        source: "codex",
        title: "测试任务",
        detail: "任务",
        status: .running,
        updatedAt: Date()
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: running, lastAssistantResult: nil, contentMode: .detailed
    ) == 99)
    #expect(DesktopConversationLayout.extraHeight(
        item: running, lastAssistantResult: nil, contentMode: .detailed
    ) == 37)

    let withActivity = WorkItem(
        id: "codex:adaptive", source: "codex", title: "测试任务", detail: "任务",
        status: .running, updatedAt: Date(), activities: [
            "检查项目规则", "读取项目文件", "运行测试", "核对界面",
        ]
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: withActivity, lastAssistantResult: nil, contentMode: .detailed
    ) == 165)
    #expect(DesktopConversationLayout.cardHeight(
        item: withActivity, lastAssistantResult: nil, contentMode: .clean
    ) == 165)

    let withWrappedActivity = WorkItem(
        id: "codex:adaptive", source: "codex", title: "测试任务", detail: "任务",
        status: .running, updatedAt: Date(), activities: [String(repeating: "长事件内容", count: 24)]
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: withWrappedActivity, lastAssistantResult: nil, contentMode: .detailed
    ) == 115)

    let waiting = WorkItem(
        id: "codex:adaptive", source: "codex", title: "测试任务", detail: "任务",
        status: .waiting, updatedAt: Date()
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: waiting, lastAssistantResult: "核心结论：已完成", contentMode: .detailed
    ) < 90)

    let longResult = String(repeating: "这是一段用于验证结果区域按内容增长且有上限的文字。", count: 20)
    #expect(DesktopConversationLayout.cardHeight(
        item: waiting, lastAssistantResult: longResult, contentMode: .detailed
    ) > 260)
    #expect(DesktopConversationLayout.completedResultLineLimit == 0)
    #expect(
        DesktopConversationLayout.defaultMeasurementWidth
            == DesktopPanelLayout.conversationContentWidth
    )
    #expect(DesktopConversationLayout.measuredTextHeight(for: longResult) > 160)
    let extremelyLongResult = String(repeating: longResult, count: 20)
    #expect(DesktopConversationLayout.cardHeight(
        item: waiting,
        lastAssistantResult: extremelyLongResult,
        contentMode: .detailed
    ) < 500)
    #expect(DesktopConversationLayout.maximumCompletedResultHeight == 360)
    #expect(
        DesktopConversationLayout.measuredTextHeight(for: longResult, width: 780)
            < DesktopConversationLayout.measuredTextHeight(for: longResult, width: 390)
    )
}

@Test func singleLineRunningConversationUsesItsActualStackHeight() {
    let running = WorkItem(
        id: "codex:compact-running",
        source: "Codex",
        title: "盘点 AI 提效工作",
        detail: "Documents",
        status: .running,
        updatedAt: Date(),
        recentActivity: "已连接 Codex，正在等待首条进度"
    )

    #expect(DesktopConversationLayout.cardHeight(
        item: running,
        lastAssistantResult: nil,
        contentMode: .clean
    ) == 99)
}

@Test func collapsedSectionAddsOnlyItsHeaderHeight() {
    let oneRunningSection = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1,
        conversationExtraHeightOverride: 36
    )
    let withCollapsedRecentSection = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 2,
        conversationExtraHeightOverride: 36
    )

    #expect(withCollapsedRecentSection.height - oneRunningSection.height == 22)
}

@Test func collapsedOnlySectionsDoNotReserveTheEmptyStateHeight() {
    let size = DesktopPanelLayout.contentSize(
        visibleItemCount: 0,
        sectionCount: 1,
        showsEmptyState: false
    )

    #expect(size.height == 175)
}

@Test func expandedRecentSectionWithTwoRowsDoesNotKeepLegacyBottomWhitespace() {
    let size = DesktopPanelLayout.contentSize(
        visibleItemCount: 2,
        sectionCount: 1,
        conversationExtraHeightOverride: 0
    )

    #expect(size.height == 299)
}

@MainActor
@Test func collapsedSectionDoesNotInsertAStretchableListSpacer() {
    let controller = DesktopStatusPanelController()
    controller.update(snapshot: WorkStatusSnapshot(items: [
        WorkItem(
            id: "codex:running",
            source: "Codex",
            title: "运行任务",
            status: .running,
            updatedAt: Date()
        ),
        WorkItem(
            id: "codex:completed",
            source: "Codex",
            title: "完成任务",
            status: .completed,
            updatedAt: Date()
        ),
    ], automationIssues: []))

    // Two section headers plus the one visible running card. The collapsed
    // recent section must not leave a fourth, stretchable arranged subview.
    #expect(controller.panelTaskArrangedSubviewCountForTesting == 3)
    controller.orderWindowsOutForTesting()
}

@Test func conversationMeasurementWidthDoesNotCollapseBeforeInitialLayout() {
    #expect(
        DesktopConversationLayout.resolvedMeasurementWidth(
            itemStackWidth: 0,
            panelContentWidth: 0
        ) == DesktopConversationLayout.defaultMeasurementWidth
    )
    #expect(
        DesktopConversationLayout.resolvedMeasurementWidth(
            itemStackWidth: 448,
            panelContentWidth: 480
        ) == 426
    )
    #expect(
        DesktopConversationLayout.resolvedMeasurementWidth(
            itemStackWidth: 448,
            panelContentWidth: 1_000
        ) == 946
    )

    let waiting = WorkItem(
        id: "codex:initial-layout",
        source: "codex",
        title: "查找 Mox 关键指标趋势链接",
        detail: "任务",
        status: .waiting,
        updatedAt: Date()
    )
    let result = "奥数中价关键指标趋势的 MOXT 链接：\n\n打开关键指标趋势图"
    let fallbackWidth = DesktopConversationLayout.resolvedMeasurementWidth(
        itemStackWidth: 0,
        panelContentWidth: 0
    )
    #expect(
        DesktopConversationLayout.cardHeight(
            item: waiting,
            lastAssistantResult: result,
            contentMode: .clean,
            measurementWidth: fallbackWidth
        ) < 180
    )

    let wideResult = """
    已修复并安装到 /Applications/AI工作岛.app。

    根因是面板首帧宽度尚未生成时，文本被按 1pt 宽度测量，导致卡片偶发被错误撑高。现在会回退到正常的 426pt 内容宽度。

    验证结果：

    - 全量 241 项测试通过
    - 发布候选 8 项闸门通过
    - 签名、单实例、数据源诊断正常
    - 安装版实际展开回读，内容已紧跟输入框
    - 已同步更新 AI_HANDOFF.md
    """
    let narrowHeight = DesktopConversationLayout.cardHeight(
        item: waiting,
        lastAssistantResult: wideResult,
        contentMode: .clean,
        measurementWidth: 426
    )
    let wideHeight = DesktopConversationLayout.cardHeight(
        item: waiting,
        lastAssistantResult: wideResult,
        contentMode: .clean,
        measurementWidth: 946
    )
    #expect(wideHeight < narrowHeight)
    let measuredWideResultHeight = DesktopConversationLayout.measuredTextHeight(
        for: wideResult,
        width: 946
    )
    #expect(wideHeight - measuredWideResultHeight == 72)
}

@Test func desktopPanelResizePolicyAllowsAUsefulWidthAndHeightRange() {
    #expect(DesktopPanelResizePolicy.minimumFrameSize == NSSize(width: 480, height: 175))
    #expect(DesktopPanelResizePolicy.maximumFrameSize == NSSize(width: 720, height: 820))
    #expect(
        DesktopPanelResizePolicy.clampedFrameSize(NSSize(width: 280, height: 900))
            == NSSize(width: 480, height: 820)
    )
    #expect(
        DesktopPanelResizePolicy.automaticallyFittedContentSize(
            NSSize(width: 372, height: 618),
            currentContentSize: NSSize(width: 500, height: 320),
            hasUserPreferredSize: false
        ) == NSSize(width: 372, height: 618)
    )
    #expect(
        DesktopPanelResizePolicy.automaticallyFittedContentSize(
            NSSize(width: 372, height: 618),
            currentContentSize: NSSize(width: 500, height: 320),
            hasUserPreferredSize: true
        ) == NSSize(width: 500, height: 618)
    )
}

@MainActor
@Test func desktopPanelRemovesUnusedHeightForEmptyAndSingleCompletedStates() {
    let controller = DesktopStatusPanelController()
    controller.update(snapshot: WorkStatusSnapshot(items: [], automationIssues: []))
    #expect(controller.panelFrameSizeForTesting.height == 205)

    let completed = WorkItem(
        id: "automation:done",
        source: "自动化",
        title: "今日任务已完成",
        status: .completed,
        updatedAt: Date()
    )
    controller.update(snapshot: WorkStatusSnapshot(items: [completed], automationIssues: []))
    #expect(controller.panelFrameSizeForTesting.height <= 177)
    controller.orderWindowsOutForTesting()
}

@Test func expandedPanelIsCenteredIndependentlyOfTheCapsulePosition() {
    let visibleFrame = NSRect(x: 120, y: 80, width: 1440, height: 900)
    let compact = DesktopPanelCenterLayout.centeredFrame(
        panelSize: NSSize(width: 480, height: 320),
        in: visibleFrame
    )
    let expanded = DesktopPanelCenterLayout.centeredFrame(
        panelSize: NSSize(width: 720, height: 746),
        in: visibleFrame
    )

    #expect(compact.midX == visibleFrame.midX)
    #expect(compact.midY == visibleFrame.midY)
    #expect(expanded.midX == visibleFrame.midX)
    #expect(expanded.midY == visibleFrame.midY)
}

@Test func expandedPanelKeepsItsTopAlignedWithTheVisibleCapsuleTop() {
    let capsule = NSRect(x: 1_300, y: 800, width: 120, height: 50)
    let compact = DesktopPanelCapsuleTopAlignment.alignedFrame(
        NSRect(x: 480, y: 300, width: 480, height: 224),
        toFloatingFrame: capsule
    )
    let tall = DesktopPanelCapsuleTopAlignment.alignedFrame(
        NSRect(x: 480, y: 120, width: 480, height: 620),
        toFloatingFrame: capsule
    )
    let visibleCapsuleTop = capsule.maxY - DesktopFloatingButtonLayout.animationInset

    #expect(compact.maxY == visibleCapsuleTop)
    #expect(tall.maxY == visibleCapsuleTop)
    #expect(compact.minY > tall.minY)
}

@Test func expandedPanelRestoresTheUserMovedPosition() {
    let visibleFrame = NSRect(x: 120, y: 80, width: 1440, height: 900)
    let restored = DesktopPanelRememberedPosition.restoredFrame(
        panelSize: NSSize(width: 480, height: 420),
        center: NSPoint(x: 500, y: 520),
        visibleFrames: [visibleFrame],
        fallbackVisibleFrame: visibleFrame
    )

    #expect(restored.origin == NSPoint(x: 260, y: 310))
}

@Test func rememberedPanelPositionReturnsToAnAvailableScreen() {
    let currentScreen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    let restored = DesktopPanelRememberedPosition.restoredFrame(
        panelSize: NSSize(width: 480, height: 420),
        center: NSPoint(x: 2_240, y: 510),
        visibleFrames: [currentScreen],
        fallbackVisibleFrame: currentScreen
    )

    #expect(restored.maxX == currentScreen.maxX)
    #expect(restored.origin.y == 300)
}

@Test func rememberedPanelCenterKeepsATallerPanelFullyVisible() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1050)
    let rememberedCenter = NSPoint(x: 1_600, y: 220)
    let restored = DesktopPanelRememberedPosition.restoredFrame(
        panelSize: NSSize(width: 498, height: 820),
        center: rememberedCenter,
        visibleFrames: [visibleFrame],
        fallbackVisibleFrame: visibleFrame
    )

    #expect(visibleFrame.contains(restored))
    #expect(restored.minY == visibleFrame.minY)
}

@Test func panelTransitionBeginsAndEndsTowardTheCapsule() {
    let target = NSRect(x: 480, y: 250, width: 480, height: 420)
    let capsule = NSRect(x: 1_300, y: 800, width: 120, height: 50)
    let hinted = DesktopPanelTransitionMotion.frameTowardSource(
        targetFrame: target,
        sourceFrame: capsule
    )

    #expect(hinted.midX > target.midX)
    #expect(hinted.midY > target.midY)
    #expect(
        abs(
            hypot(hinted.midX - target.midX, hinted.midY - target.midY)
                - DesktopPanelTransitionMotion.travel
        ) < 0.001
    )
}

@Test func panelTransitionScalesContinuouslyTowardItsCapsuleSource() {
    let target = NSRect(x: 480, y: 250, width: 480, height: 420)
    let capsule = NSRect(x: 1_300, y: 800, width: 120, height: 50)
    let expandedStart = DesktopPanelTransitionMotion.frameTowardSource(
        targetFrame: target,
        sourceFrame: capsule,
        travel: DesktopPanelTransitionMotion.expandTravel,
        scale: DesktopPanelTransitionMotion.expandSourceScale
    )
    let collapsedEnd = DesktopPanelTransitionMotion.frameTowardSource(
        targetFrame: target,
        sourceFrame: capsule,
        travel: DesktopPanelTransitionMotion.collapseTravel,
        scale: DesktopPanelTransitionMotion.collapseSourceScale
    )

    #expect(expandedStart.width == target.width * 0.94)
    #expect(expandedStart.height == target.height * 0.94)
    #expect(collapsedEnd.width == target.width * 0.965)
    #expect(collapsedEnd.height == target.height * 0.965)
    #expect(expandedStart.midX > target.midX)
    #expect(expandedStart.midY > target.midY)
    #expect(collapsedEnd.midX > target.midX)
    #expect(collapsedEnd.midY > target.midY)
}

@Test func completionExpansionReplaysTheCollapseInReverse() {
    #expect(DesktopLiquidMotion.expandDuration > DesktopLiquidMotion.collapseDuration)
    #expect(DesktopLiquidMotion.morphDuration >= DesktopLiquidMotion.collapseDuration)
    #expect(DesktopLiquidMotion.morphDuration == 0.24)
    #expect(DesktopLiquidMotion.completionMorphCollapseDuration == 0.24)
    #expect(DesktopLiquidMotion.morphDuration == DesktopLiquidMotion.completionMorphCollapseDuration)
    #expect(DesktopLiquidMotion.estimatedFrameCount(
        duration: DesktopLiquidMotion.morphDuration,
        refreshRate: 60
    ) >= 15)
    #expect(DesktopLiquidMotion.hoverDuration < DesktopLiquidMotion.collapseDuration)
    #expect(DesktopLiquidMotion.resizeDuration <= 0.3)
    #expect(DesktopLiquidMotion.estimatedFrameCount(
        duration: DesktopLiquidMotion.expandDuration,
        refreshRate: 60
    ) >= 16)
    #expect(DesktopLiquidMotion.estimatedFrameCount(
        duration: DesktopLiquidMotion.expandDuration,
        refreshRate: 120
    ) >= 32)
    #expect(DesktopLiquidMotion.expandDuration < 0.30)
    #expect(
        DesktopLiquidMotion.contentEntranceDelay
            + DesktopLiquidMotion.contentEntranceDuration
            <= DesktopLiquidMotion.expandDuration
    )
}

@Test func aStalePresentationCompletionCannotEndANewerTransition() {
    var transition = DesktopWindowPresentationTransition()
    let first = transition.begin()
    let second = transition.begin()
    let staleFinished = transition.finish(first)

    #expect(!staleFinished)
    #expect(transition.isActive(second))
    #expect(transition.suppressesPositionSynchronization)
    let currentFinished = transition.finish(second)
    #expect(currentFinished)
    #expect(!transition.suppressesPositionSynchronization)
}

@MainActor
@Test func panelPresentationMovementDoesNotRewriteAnEdgeSnappedCapsuleAnchor() {
    let controller = DesktopStatusPanelController()
    let edgeFrame = NSRect(x: -6, y: -6, width: 120, height: 50)
    controller.setCollapsedFrameForTesting(edgeFrame)
    let originalAnchor = controller.sharedAnchorForTesting
    let originalPreferredCenter = controller.userPreferredPanelCenterForTesting
    let generation = controller.beginPresentationTransitionForTesting()

    controller.notifyPanelMoveForTesting(to: NSRect(x: 420, y: 240, width: 480, height: 420))

    #expect(controller.sharedAnchorForTesting == originalAnchor)
    #expect(controller.userPreferredPanelCenterForTesting == originalPreferredCenter)
    #expect(controller.floatingPanelFrameForTesting == edgeFrame)
    controller.finishPresentationTransitionForTesting(generation)
    controller.hide()
}

@MainActor
@Test func movingExpandedPanelDoesNotMoveCollapsedCapsule() {
    let controller = DesktopStatusPanelController()
    let capsuleFrame = NSRect(x: 1_200, y: 700, width: 120, height: 50)
    controller.setCollapsedFrameForTesting(capsuleFrame)
    let originalAnchor = controller.sharedAnchorForTesting
    let movedPanelFrame = NSRect(x: 420, y: 240, width: 480, height: 420)

    controller.notifyPanelMoveForTesting(to: movedPanelFrame)

    #expect(controller.floatingPanelFrameForTesting == capsuleFrame)
    #expect(controller.sharedAnchorForTesting == originalAnchor)
    #expect(controller.userPreferredPanelCenterForTesting == NSPoint(
        x: movedPanelFrame.midX,
        y: movedPanelFrame.midY
    ))
    controller.hide()
}

@MainActor
@Test func edgeSnappedCapsuleReturnsToTheExactFrameAfterExpandAndCollapse() async {
    let controller = DesktopStatusPanelController()
    let edgeFrame = NSRect(origin: NSPoint(x: -6, y: 300), size: DesktopFloatingButtonLayout.canvasSize)
    controller.setCollapsedFrameForTesting(edgeFrame)

    await controller.runExpandCollapseCycleForTesting()

    #expect(controller.floatingPanelIsVisibleForTesting)
    #expect(!controller.panelIsVisibleForTesting)
    #expect(controller.floatingPanelFrameForTesting == edgeFrame)
    #expect(
        controller.sharedAnchorForTesting
            == DesktopPanelAnchorLayout.anchor(fromFloatingFrame: edgeFrame)
    )
    controller.hide()
}

@Test func desktopPanelUsesTheSelectedAdaptiveGlassPalette() {
    let dark = NSAppearance(named: .darkAqua)!
    var base: NSColor?
    var card: NSColor?
    var input: NSColor?
    dark.performAsCurrentDrawingAppearance {
        base = DesktopPanelPalette.base.usingColorSpace(.sRGB)
        card = DesktopPanelPalette.card.usingColorSpace(.sRGB)
        input = DesktopPanelPalette.input.usingColorSpace(.sRGB)
    }

    let accuracy = 1.0e-12
    #expect(abs((base?.redComponent ?? -1) - 43.0 / 255.0) < accuracy)
    #expect(abs((base?.greenComponent ?? -1) - 43.0 / 255.0) < accuracy)
    #expect(abs((base?.blueComponent ?? -1) - 43.0 / 255.0) < accuracy)
    #expect(abs((card?.redComponent ?? -1) - 60.0 / 255.0) < accuracy)
    #expect(abs((input?.redComponent ?? -1) - 36.0 / 255.0) < accuracy)

    let light = NSAppearance(named: .aqua)!
    var lightBase: NSColor?
    light.performAsCurrentDrawingAppearance {
        lightBase = DesktopPanelPalette.base.usingColorSpace(.sRGB)
    }
    #expect(abs((lightBase?.redComponent ?? -1) - 246.0 / 255.0) < accuracy)
    #expect(abs((lightBase?.greenComponent ?? -1) - 246.0 / 255.0) < accuracy)
    #expect(abs((lightBase?.blueComponent ?? -1) - 246.0 / 255.0) < accuracy)
}

@Test func desktopPanelNeutralSurfacesDoNotCarryAnAccentBlueTint() {
    let appearances = [NSAppearance(named: .aqua)!, NSAppearance(named: .darkAqua)!]
    let colors = [
        DesktopPanelPalette.base,
        DesktopPanelPalette.card,
        DesktopPanelPalette.hoveredCard,
        DesktopPanelPalette.input,
        DesktopPanelPalette.stroke,
    ]

    for appearance in appearances {
        appearance.performAsCurrentDrawingAppearance {
            for color in colors {
                let resolved = color.usingColorSpace(.sRGB)!
                #expect(abs(resolved.redComponent - resolved.greenComponent) < 0.001)
                #expect(abs(resolved.blueComponent - resolved.greenComponent) < 0.001)
            }
        }
    }
}

@Test func appearanceModesMapToSystemLightAndDark() {
    #expect(AppAppearanceMode.system.appearance == nil)
    #expect(AppAppearanceMode.light.appearance?.name == .aqua)
    #expect(AppAppearanceMode.dark.appearance?.name == .darkAqua)
}

@Test func completedResultMarkerAlignsWithTheFirstTextLine() {
    #expect(DesktopConversationLayout.completedResultMarkerTopInset == 0)
}

@MainActor
@Test func completedResultRendersMarkdownTablesWithoutSyntaxRows() {
    let markdown = """
    结论：

    | 推荐度 | 项目 | 状态 |
    |---|---|---|
    | 1 | btt-window-manager-preset | 2026 年仍维护 |
    | 2 | btt-config | 2026 年更新 |
    """

    let rendered = DesktopResultTextRenderer.attributedString(for: markdown)
    #expect(DesktopResultTextRenderer.containsTable(in: markdown))
    #expect(!rendered.string.contains("|---|"))
    #expect(!rendered.string.contains("| 推荐度 |"))
    #expect(rendered.string.contains("btt-window-manager-preset"))
    var hasTableBlock = false
    rendered.enumerateAttribute(
        .paragraphStyle,
        in: NSRange(location: 0, length: rendered.length)
    ) { value, _, stop in
        guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty else { return }
        hasTableBlock = true
        stop.pointee = true
    }
    #expect(hasTableBlock)
}

@Test func panelLayerColorsResolveAgainstTheSelectedWindowAppearance() {
    let dark = NSAppearance(named: .darkAqua)!
    let light = NSAppearance(named: .aqua)!
    var lightCard: CGColor?

    dark.performAsCurrentDrawingAppearance {
        lightCard = DesktopPanelPalette.card.cgColor(resolvedFor: light)
    }

    let components = lightCard?.components ?? []
    #expect(components.count >= 3)
    #expect(abs(components[0] - 1) < 1.0e-12)
    #expect(abs(components[1] - 1) < 1.0e-12)
    #expect(abs(components[2] - 1) < 1.0e-12)
}

@Test func voiceMemoGuardianRequiresSustainedQuietBeforeReminding() {
    let now = Date(timeIntervalSince1970: 10_000)
    #expect(VoiceMemoSilencePolicy.isSilent(meanDB: -50, peakDB: -35))
    #expect(!VoiceMemoSilencePolicy.isSilent(meanDB: -40, peakDB: -35))
    #expect(!VoiceMemoSilencePolicy.isSilent(meanDB: -50, peakDB: -20))
    #expect(!VoiceMemoSilencePolicy.shouldRemind(
        silentSince: now.addingTimeInterval(-299),
        now: now
    ))
    #expect(VoiceMemoSilencePolicy.shouldRemind(
        silentSince: now.addingTimeInterval(-300),
        now: now
    ))
}

@Test func voiceMemoWaveformNormalizesWithoutRetainingAudioSamples() {
    #expect(VoiceMemoWaveformPolicy.normalizedLevel(meanDB: -80, peakDB: -75) == 0)
    #expect(VoiceMemoWaveformPolicy.normalizedLevel(meanDB: -6, peakDB: -3) == 1)
    let conversational = VoiceMemoWaveformPolicy.normalizedLevel(meanDB: -28, peakDB: -18)
    #expect(conversational > 0.5 && conversational < 1)
}

@MainActor
@Test func recordingWaveformUsesSevenBoundedBars() {
    let waveform = RecordingWaveformView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
    waveform.layoutSubtreeIfNeeded()
    waveform.update(level: 0.7, tintColor: .systemRed)
    let heights = waveform.heightsForTesting()

    #expect(heights.count == 7)
    #expect(heights.allSatisfy { $0 >= 2 && $0 <= 15 })
    #expect(Set(heights.map { Int($0.rounded()) }).count > 1)
}

@MainActor
@Test func recordingWaveformIsRemovedWhenRecordingEnds() {
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size)
    )
    view.updateRecordingGuardian(
        VoiceMemoGuardianState(phase: .recording, startedAt: Date(), silentSince: nil)
    )
    #expect(view.isRecordingWaveformVisibleForTesting())

    view.updateRecordingGuardian(nil)
    #expect(!view.isRecordingWaveformVisibleForTesting())
}

@MainActor @Test func recordingCapsuleOffersAnExplicitStopAction() {
    let view = FloatingStatusButtonView(frame: NSRect(x: 0, y: 0, width: 108, height: 38))
    var stopped = false
    view.onStopRecording = { stopped = true }
    view.updateRecordingGuardian(
        VoiceMemoGuardianState(phase: .recording, startedAt: Date(), silentSince: nil)
    )
    #expect(view.isStopRecordingVisibleForTesting())
    view.stopRecordingForTesting()
    #expect(stopped)
    #expect(view.isRecordingStopInProgressForTesting())
    view.stopRecordingForTesting()
    #expect(stopped)
    view.updateRecordingGuardian(nil)
    #expect(!view.isStopRecordingVisibleForTesting())
}

@MainActor
@Test func hiddenRecordingStopButtonDoesNotTruncateCompanyQuota() {
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size)
    )
    let quota = CompanyModelQuota(
        totalUSD: 200,
        usedUSD: 28.12,
        resetsAt: nil
    )
    view.update(snapshot: WorkStatusSnapshot(items: [], automationIssues: [], companyQuota: quota))
    view.advanceCarousel()
    view.layoutSubtreeIfNeeded()

    #expect(view.displayedTextForTesting() == "公司 86%")
    #expect(view.statusLabelHasEnoughWidthForTesting())
}

@Test func voiceMemoGuardianOverridesTheFloatingPillWithRecordingState() {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    let now = startedAt.addingTimeInterval(42 * 60)
    let recording = DesktopFloatingButtonPresentation.recordingGuardian(
        VoiceMemoGuardianState(phase: .recording, startedAt: startedAt, silentSince: nil),
        now: now
    )
    let silence = DesktopFloatingButtonPresentation.recordingGuardian(
        VoiceMemoGuardianState(
            phase: .silence,
            startedAt: startedAt,
            silentSince: now.addingTimeInterval(-5 * 60)
        ),
        now: now
    )

    #expect(recording.displayText == "录音 42分")
    #expect(recording.tintColor == .systemRed)
    #expect(recording.pulses)
    #expect(silence.displayText == "静音 5分")
    #expect(silence.tintColor == .systemOrange)
    #expect(!silence.pulses)
}

@Test func floatingStatusButtonUsesACompactPillHitTarget() {
    #expect(DesktopFloatingButtonLayout.size == NSSize(width: 108, height: 38))
    #expect(DesktopFloatingButtonLayout.canvasSize == NSSize(width: 120, height: 56))
    #expect(DesktopFloatingButtonLayout.completionSize == NSSize(width: 288, height: 64))
    #expect(DesktopFloatingButtonLayout.completionCanvasSize == NSSize(width: 300, height: 82))
    #expect(DesktopFloatingButtonLayout.animationInset == 6)
    #expect(DesktopFloatingButtonLayout.cornerRadius == 19)
    #expect(
        DesktopFloatingButtonLayout.completionCornerRadius
            == DesktopFloatingButtonLayout.cornerRadius
    )
    #expect(DesktopLiquidMotion.completionMarqueeOrbitDuration == 1.8)
    #expect(DesktopFloatingButtonLayout.statusDotSize == 8)
}

@MainActor
@Test func floatingCapsuleUsesOnlyItsRoundedLayerWithoutARectangularWindowShadow() {
    let controller = DesktopStatusPanelController()
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size)
    )
    view.layoutSubtreeIfNeeded()

    #expect(!controller.floatingPanelHasWindowShadowForTesting)
    #expect(view.layer?.masksToBounds == true)
    #expect(view.layer?.cornerRadius == DesktopFloatingButtonLayout.size.height / 2)
    controller.hide()
}

@Test func conversationCardKeepsTitleHeaderToOneLine() {
    #expect(DesktopConversationLayout.compactHeaderHeight == 32)
    #expect(DesktopConversationLayout.titleLineLimit == 1)
    #expect(DesktopConversationLayout.titleHeaderHeight(
        for: "短标题", width: 420
    ) == DesktopConversationLayout.compactHeaderHeight)
    #expect(DesktopConversationLayout.titleHeaderHeight(
        for: String(repeating: "这是需要完整显示的会话标题", count: 8),
        width: 260
    ) == DesktopConversationLayout.compactHeaderHeight)
    let item = WorkItem(
        id: "codex:running-title",
        source: "Codex",
        title: "学科业务",
        status: .running,
        updatedAt: Date(),
        activities: [
            "第一段较长的公开正文，用于占据多行空间。",
            "第二段较长的公开正文，用于确认标题不会被向上挤压裁切。",
            "第三段较长的公开正文，用于覆盖详细卡片的高密度场景。",
            "第四段较长的公开正文，用于覆盖可见正文上限。",
        ]
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: item,
        lastAssistantResult: nil,
        contentMode: .detailed
    ) == 165)
}

@Test func expandedPanelReservesAnUncompressedMainTitleHeader() {
    #expect(DesktopPanelHeaderLayout.minimumHeight >= 24)
}

@Test func denseRunningCardCompressesHistoryButKeepsTheCurrentUpdateReadable() {
    let long = String(repeating: "这是一条需要多行展示的公开任务动态。", count: 8)
    let item = WorkItem(
        id: "codex:dense-running",
        source: "Codex",
        title: "学科业务",
        status: .running,
        updatedAt: Date(),
        activities: [long, long, long, long]
    )
    #expect(DesktopConversationLayout.cardHeight(
        item: item,
        lastAssistantResult: nil,
        contentMode: .detailed
    ) == 115)
}

@MainActor
@Test func completionCapsuleShowsTaskAndStageWithoutOpeningTheMainPanel() async throws {
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.completionSize)
    )
    let item = WorkItem(
        id: "codex:done",
        source: "Codex",
        title: "修改 AI工作岛",
        status: .running,
        updatedAt: Date(),
        phase: "验证安装版",
        phaseIndex: 2,
        phaseCount: 3
    )

    view.showCompletion(item: item, result: nil)
    #expect(view.isCompletionVisibleForTesting())
    #expect(view.motionSnapshot().statusLabel.contains("completionOutgoingContentExit"))
    try await Task.sleep(nanoseconds: 150_000_000)
    #expect(view.displayedTextForTesting() == "修改 AI工作岛")
    #expect(view.displayedDetailForTesting() == "已完成 3/3 · 验证安装版")
    view.clearCompletion()
    #expect(!view.isCompletionVisibleForTesting())
}

@MainActor
@Test func finishingAHiddenTaskExpandsOnlyTheSummaryCapsule() {
    let now = Date(timeIntervalSince1970: 200)
    let controller = DesktopStatusPanelController()
    controller.showCollapsed()
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:1", source: "Codex", title: "分析任务",
            status: .running, updatedAt: now, phase: "读取资料"
        )],
        automationIssues: []
    ))
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:1", source: "Codex", title: "分析任务",
            status: .waiting, updatedAt: now.addingTimeInterval(1)
        )],
        automationIssues: []
    ))

    #expect(!controller.panelIsVisibleForTesting)
    #expect(controller.floatingPanelIsVisibleForTesting)
    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.completionCanvasSize)
    controller.hide()
}

@MainActor
@Test func finishingAViewedTaskThatLeavesTheListStillExpandsTheSummaryCapsule() {
    let now = Date(timeIntervalSince1970: 225)
    let controller = DesktopStatusPanelController()
    controller.showCollapsed()
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:viewed", source: "Codex", title: "已查看任务",
            status: .running, updatedAt: now, phase: "正在收尾"
        )],
        automationIssues: []
    ))
    controller.update(snapshot: WorkStatusSnapshot(items: [], automationIssues: []))

    #expect(!controller.panelIsVisibleForTesting)
    #expect(controller.floatingPanelIsVisibleForTesting)
    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.completionCanvasSize)
    #expect(controller.floatingButtonMotionForTesting.shellMask.contains("completionShellMorph"))
    controller.hide()
}

@MainActor
@Test func collapsedWindowRepairsStaleCompletionContentConstraints() {
    let now = Date(timeIntervalSince1970: 200)
    let controller = DesktopStatusPanelController()
    controller.showCollapsed()
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:1", source: "Codex", title: "分析任务",
            status: .running, updatedAt: now, phase: "读取资料"
        )],
        automationIssues: []
    ))
    controller.update(snapshot: WorkStatusSnapshot(
        items: [WorkItem(
            id: "codex:1", source: "Codex", title: "分析任务",
            status: .waiting, updatedAt: now.addingTimeInterval(1)
        )],
        automationIssues: []
    ))
    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.completionCanvasSize)

    // A racing window animation can finish at the compact outer frame while
    // the inner completion constraints are still wide. Collapsing must repair both.
    controller.setCollapsedFrameForTesting(NSRect(
        origin: .zero,
        size: DesktopFloatingButtonLayout.canvasSize
    ))
    controller.showCollapsed()

    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.canvasSize)
    controller.hide()
}

@MainActor
@Test func interruptedCompletionCollapseStillRestoresTheCompactCapsule() async throws {
    let now = Date(timeIntervalSince1970: 205)
    let controller = DesktopStatusPanelController()
    controller.showCollapsed()
    controller.update(snapshot: WorkStatusSnapshot(items: [WorkItem(
        id: "codex:interrupted-collapse",
        source: "Codex",
        title: "缩回被系统打断",
        status: .running,
        updatedAt: now
    )], automationIssues: []))
    controller.update(snapshot: WorkStatusSnapshot(items: [WorkItem(
        id: "codex:interrupted-collapse",
        source: "Codex",
        title: "缩回被系统打断",
        status: .waiting,
        updatedAt: now.addingTimeInterval(1)
    )], automationIssues: []))

    controller.startCompletionCollapseForTesting()
    controller.interruptCompletionCollapseForTesting()
    try await Task.sleep(for: .milliseconds(400))

    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.canvasSize)
    #expect(!controller.floatingButtonIsShowingCompletionForTesting)
    #expect(controller.floatingButtonCompactVisualIsRestoredForTesting)
    controller.hide()
}

@MainActor
@Test func completionCollapseKeepsItsExpandedHostUntilTheMaskFinishes() {
    let now = Date(timeIntervalSince1970: 250)
    let controller = DesktopStatusPanelController()
    controller.showCollapsed()
    controller.update(snapshot: WorkStatusSnapshot(items: [WorkItem(
        id: "codex:freeze-collapse-host",
        source: "Codex",
        title: "冻结缩回宿主",
        status: .running,
        updatedAt: now,
        phase: "执行"
    )], automationIssues: []))
    controller.update(snapshot: WorkStatusSnapshot(items: [WorkItem(
        id: "codex:freeze-collapse-host",
        source: "Codex",
        title: "冻结缩回宿主",
        status: .waiting,
        updatedAt: now.addingTimeInterval(1)
    )], automationIssues: []))

    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.completionCanvasSize)
    controller.startCompletionCollapseForTesting()
    #expect(controller.floatingPanelSizeForTesting == DesktopFloatingButtonLayout.completionCanvasSize)
    controller.hide()
}

@Test func desktopWindowsSnapToEachVisibleScreenEdge() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let rightTop = DesktopWindowEdgeSnap.snappedFrame(
        NSRect(x: 1_335, y: 814, width: 100, height: 80),
        in: visibleFrame
    )
    #expect(rightTop.origin == NSPoint(x: 1_340, y: 820))

    let leftBottom = DesktopWindowEdgeSnap.snappedFrame(
        NSRect(x: 12, y: 8, width: 372, height: 280),
        in: visibleFrame
    )
    #expect(leftBottom.origin == .zero)
}

@Test func floatingPillSnapsItsVisibleCapsuleRatherThanItsTransparentCanvas() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    let inset = DesktopFloatingButtonLayout.animationInset
    let snapped = DesktopWindowEdgeSnap.snappedFrame(
        NSRect(x: 1_326, y: 5, width: 120, height: 50),
        in: visibleFrame,
        contentInsets: NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    )
    #expect(snapped.origin == NSPoint(x: 1_326, y: -6))
}

@Test func floatingPillIsClampedBackInsideTheCurrentScreen() {
    let screen = NSRect(x: 0, y: 89, width: 1_440, height: 781)
    let offscreen = NSRect(x: 680, y: 915, width: 120, height: 50)
    let inset = DesktopFloatingButtonLayout.animationInset
    let clamped = DesktopWindowVisibility.clampedFrame(
        offscreen,
        in: screen,
        contentInsets: NSEdgeInsets(top: inset, left: inset, bottom: inset, right: inset)
    )

    #expect(clamped.origin.x == 680)
    #expect(clamped.maxY - inset == screen.maxY)
}

@Test func expandedPanelShrinksWhenTheNewResolutionCannotFitItsRememberedHeight() {
    let screen = NSRect(x: 0, y: 90, width: 1_504, height: 726)
    let remembered = NSRect(x: 1_422, y: -65, width: 480, height: 820)
    let clamped = DesktopWindowVisibility.clampedFrame(remembered, in: screen)

    #expect(clamped.size == NSSize(width: 480, height: 726))
    #expect(clamped.maxX == screen.maxX)
    #expect(clamped.minY == screen.minY)
    #expect(screen.contains(clamped))
}

@Test func expandedPanelAndCollapsedPillShareTheSameTopRightAnchor() {
    let floatingFrame = NSRect(x: 1_320, y: 840, width: 120, height: 50)
    let inset = DesktopFloatingButtonLayout.animationInset
    let panelFrame = DesktopPanelAnchorLayout.panelFrame(
        anchoredToFloatingPanel: floatingFrame,
        panelSize: NSSize(width: 372, height: 290)
    )
    #expect(panelFrame.maxX == floatingFrame.maxX - inset)
    #expect(panelFrame.maxY == floatingFrame.maxY - inset)

    let restoredFloatingFrame = DesktopPanelAnchorLayout.floatingFrame(
        anchoredToPanel: panelFrame,
        floatingSize: floatingFrame.size
    )
    #expect(restoredFloatingFrame == floatingFrame)
}

@Test func sharedWindowAnchorSurvivesPanelResizeAndFloatingCanvasInset() {
    let anchor = NSPoint(x: 1_440, y: 840)
    let panel = DesktopPanelAnchorLayout.panelFrame(
        anchoredTo: anchor,
        panelSize: NSSize(width: 334, height: 364)
    )
    let resizedPanel = DesktopPanelAnchorLayout.panelFrame(
        anchoredTo: anchor,
        panelSize: NSSize(width: 620, height: 746)
    )
    let floating = DesktopPanelAnchorLayout.floatingFrame(
        anchoredTo: anchor,
        floatingSize: DesktopFloatingButtonLayout.canvasSize
    )

    #expect(DesktopPanelAnchorLayout.anchor(fromPanelFrame: panel) == anchor)
    #expect(DesktopPanelAnchorLayout.anchor(fromPanelFrame: resizedPanel) == anchor)
    #expect(DesktopPanelAnchorLayout.anchor(fromFloatingFrame: floating) == anchor)
}

@Test func floatingStatusButtonPrioritizesLiveStatus() {
    let completed = WorkItem(
        id: "done",
        source: "自动化",
        title: "日报完成",
        status: .completed,
        updatedAt: Date(),
        outputPath: "/tmp/output"
    )
    let running = WorkItem(
        id: "running",
        source: "Codex",
        title: "分析中",
        status: .running,
        updatedAt: Date()
    )
    let waiting = WorkItem(
        id: "waiting",
        source: "Codex",
        title: "等待确认",
        status: .waiting,
        updatedAt: Date()
    )

    let activePresentation = DesktopFloatingButtonPresentation.make(
        items: [running, completed],
        latestCompleted: completed
    )
    let waitingPresentation = DesktopFloatingButtonPresentation.make(
        items: [waiting, running, completed],
        latestCompleted: completed
    )
    let completedPresentation = DesktopFloatingButtonPresentation.make(
        items: [completed],
        latestCompleted: completed
    )
    let idlePresentation = DesktopFloatingButtonPresentation.make(items: [], latestCompleted: nil)

    #expect(activePresentation.displayText == "1 运行")
    #expect(activePresentation.tintColor == .systemBlue)
    #expect(activePresentation.pulses)
    #expect(activePresentation.isRunning)
    #expect(waitingPresentation.displayText == "1 等待你")
    #expect(waitingPresentation.tintColor == .systemOrange)
    #expect(!waitingPresentation.pulses)
    #expect(waitingPresentation.isRunning)
    #expect(completedPresentation.displayText == "已完成")
    #expect(completedPresentation.tintColor == .systemGreen)
    #expect(idlePresentation.displayText == "空闲")
    #expect(idlePresentation.tintColor == .secondaryLabelColor)
    #expect(!idlePresentation.isRunning)
    #expect(activePresentation.accessibilityLabel == "恢复 AI工作岛；当前1 运行")

    let queuedPresentation = DesktopFloatingButtonPresentation.make(
        items: [WorkItem(
            id: "queued", source: "Codex", title: "排队任务",
            status: .queued, updatedAt: Date()
        )],
        latestCompleted: nil
    )
    #expect(queuedPresentation.displayText == "1 排队")
    #expect(!queuedPresentation.pulses)
    #expect(!queuedPresentation.isRunning)
}

@Test func floatingStatusButtonMotionHonorsReduceMotionAndMeaningfulChanges() {
    let idle = DesktopFloatingButtonPresentation.make(items: [], latestCompleted: nil)
    let runningItem = WorkItem(
        id: "running",
        source: "Codex",
        title: "分析中",
        status: .running,
        updatedAt: Date()
    )
    let running = DesktopFloatingButtonPresentation.make(items: [runningItem], latestCompleted: nil)

    #expect(!DesktopFloatingButtonMotion.shouldAnimateTransition(from: nil, to: idle, reduceMotion: false))
    #expect(!DesktopFloatingButtonMotion.shouldAnimateTransition(from: idle, to: idle, reduceMotion: false))
    #expect(!DesktopFloatingButtonMotion.shouldAnimateTransition(from: idle, to: running, reduceMotion: true))
    #expect(DesktopFloatingButtonMotion.shouldAnimateTransition(from: idle, to: running, reduceMotion: false))
    #expect(DesktopFloatingButtonMotion.entranceDuration >= 0.3)
    #expect(DesktopFloatingButtonMotion.entranceDuration <= 0.4)
    #expect(DesktopFloatingButtonMotion.transitionDuration <= 0.25)
    #expect(DesktopFloatingButtonMotion.completionContentDelay == 0)
    #expect(DesktopFloatingButtonMotion.completionContentDuration == 0.10)
    #expect(DesktopFloatingButtonMotion.completionContentStagger == 0)
    #expect(DesktopFloatingButtonMotion.carouselInterval == 4)
}

@Test func floatingStatusCarouselIncludesEveryAvailableQuota() {
    let recordedAt = Date(timeIntervalSince1970: 100)
    let snapshot = WorkStatusSnapshot(
        items: [],
        automationIssues: [],
        codexShortTermLimit: WeeklyLimitUsage(
            usedPercent: 29,
            resetsAt: nil,
            recordedAt: recordedAt
        ),
        codexWeeklyLimit: WeeklyLimitUsage(
            usedPercent: 42,
            resetsAt: nil,
            recordedAt: recordedAt
        ),
        companyQuota: CompanyModelQuota(totalUSD: 200, usedUSD: 50, resetsAt: nil)
    )

    let pages = DesktopFloatingButtonPresentation.carousel(for: snapshot)

    #expect(pages.map(\.displayText) == ["空闲", "公司 75%", "5时 71%", "周 58%"])
    #expect(pages[1].tintColor == .systemPurple)
    #expect(pages[2].tintColor == .systemTeal)
    #expect(pages[3].tintColor == .systemIndigo)
    #expect(pages.dropFirst().map(\.pulses) == [false, false, false])
}

@Test func floatingStatusCarouselPromptsForCompanyQuotaWhenNotConfigured() {
    let pages = DesktopFloatingButtonPresentation.carousel(for: WorkStatusSnapshot(
        items: [],
        automationIssues: []
    ))

    #expect(pages.map(\.displayText) == ["空闲", "公司 待配置"])
    #expect(pages[1].accessibilityLabel.contains("Edge 登录公司模型平台"))
}

@Test func floatingStatusCarouselKeepsAttentionVisibleInsteadOfRotatingQuota() {
    let waiting = WorkItem(
        id: "waiting",
        source: "Codex",
        title: "等待确认",
        status: .waiting,
        updatedAt: Date()
    )
    let pages = DesktopFloatingButtonPresentation.carousel(for: WorkStatusSnapshot(
        items: [waiting],
        automationIssues: [],
        codexWeeklyLimit: WeeklyLimitUsage(
            usedPercent: 30,
            resetsAt: nil,
            recordedAt: Date()
        )
    ))

    #expect(pages.map(\.displayText) == ["1 等待你"])
}

@Test func floatingStatusCarouselKeepsFailuresVisibleWithAccessiblePriorityState() {
    let failed = WorkItem(
        id: "failed",
        source: "自动化",
        title: "日报发布",
        status: .failed,
        updatedAt: Date()
    )
    let snapshot = WorkStatusSnapshot(
        items: [failed],
        automationIssues: [],
        codexWeeklyLimit: WeeklyLimitUsage(
            usedPercent: 15,
            resetsAt: nil,
            recordedAt: Date()
        ),
        companyQuota: CompanyModelQuota(totalUSD: 20, usedUSD: 18, resetsAt: nil)
    )

    let pages = DesktopFloatingButtonPresentation.carousel(for: snapshot)

    #expect(pages.count == 1)
    #expect(pages[0].displayText == "1 需处理")
    #expect(pages[0].tintColor == .systemRed)
    #expect(!pages[0].pulses)
    #expect(pages[0].accessibilityLabel == "恢复 AI工作岛；当前1 需处理")
}

@MainActor
@Test func floatingStatusButtonAdvancesAndWrapsTheQuotaCarousel() {
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size)
    )
    let recordedAt = Date(timeIntervalSince1970: 100)
    let snapshot = WorkStatusSnapshot(
        items: [],
        automationIssues: [],
        codexShortTermLimit: WeeklyLimitUsage(
            usedPercent: 29,
            resetsAt: nil,
            recordedAt: recordedAt
        ),
        codexWeeklyLimit: WeeklyLimitUsage(
            usedPercent: 42,
            resetsAt: nil,
            recordedAt: recordedAt
        )
    )
    view.update(snapshot: snapshot)

    #expect(view.displayedTextForTesting() == "空闲")
    view.advanceCarousel()
    #expect(view.displayedTextForTesting() == "公司 待配置")
    view.update(snapshot: snapshot)
    #expect(view.displayedTextForTesting() == "公司 待配置")
    view.advanceCarousel()
    #expect(view.displayedTextForTesting() == "5时 71%")
    view.advanceCarousel()
    #expect(view.displayedTextForTesting() == "周 58%")
    view.advanceCarousel()
    #expect(view.displayedTextForTesting() == "空闲")
}

@MainActor
@Test func floatingStatusButtonRestoresThePanelOnHover() {
    let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
    var didRequestRestore = false
    view.onHoverEntered = { didRequestRestore = true }

    view.handleHoverEntered()

    #expect(didRequestRestore)

    didRequestRestore = false
    view.suppressHoverActivationUntilPointerExit(true)
    view.handleHoverEntered()
    #expect(!didRequestRestore)
    view.pointerExitForTesting()
    view.handleHoverEntered()
    #expect(didRequestRestore)
}

@MainActor
@Test func floatingStatusButtonExpandsImmediatelyBecauseDraggingHasItsOwnHandle() {
    let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
    var didRequestRestore = false
    view.onHoverEntered = { didRequestRestore = true }

    view.scheduleHoverActivationForTesting()

    #expect(FloatingStatusButtonView.hoverActivationDelay == 0)
    #expect(!view.hasPendingHoverActivationForTesting())
    #expect(didRequestRestore)
    #expect(DesktopFloatingButtonLayout.dragHandleSize == NSSize(width: 26, height: 6))
    #expect(DesktopFloatingButtonLayout.canvasSize.height == 56)
}

@Test func restoredPanelCannotBeHiddenByAStaleMinimizeAnimation() {
    #expect(DesktopFloatingPanelTransition.shouldFinishMinimizing(isMinimizedToFloatingButton: true))
    #expect(!DesktopFloatingPanelTransition.shouldFinishMinimizing(isMinimizedToFloatingButton: false))
}

@Test func hoverExpandedPanelCollapsesOnlyAfterThePointerLeaves() {
    #expect(DesktopFloatingHoverBehavior.collapseDelay == 0.25)
    #expect(DesktopFloatingHoverBehavior.panelTravelGrace == 0.75)
    #expect(DesktopFloatingHoverBehavior.layoutChangeGrace == 0.6)
    #expect(DesktopFloatingHoverBehavior.hoverReconciliationInterval == 0.1)
    #expect(!DesktopFloatingHoverBehavior.shouldAutoCollapse(isHoverExpanded: false, isPanelHovered: false))
    #expect(!DesktopFloatingHoverBehavior.shouldAutoCollapse(isHoverExpanded: true, isPanelHovered: true))
    #expect(DesktopFloatingHoverBehavior.shouldAutoCollapse(isHoverExpanded: true, isPanelHovered: false))
    #expect(DesktopFloatingHoverBehavior.shouldScheduleAutoCollapse(
        isHoverExpanded: true,
        isPanelHovered: false,
        hasPendingAutoCollapse: false
    ))
    #expect(!DesktopFloatingHoverBehavior.shouldScheduleAutoCollapse(
        isHoverExpanded: true,
        isPanelHovered: false,
        hasPendingAutoCollapse: true
    ))
    #expect(!DesktopFloatingHoverBehavior.shouldScheduleAutoCollapse(
        isHoverExpanded: true,
        isPanelHovered: false,
        hasPendingAutoCollapse: false,
        suppressionExpiresAt: Date(timeIntervalSince1970: 101),
        now: Date(timeIntervalSince1970: 100)
    ))
    #expect(DesktopFloatingHoverBehavior.shouldScheduleAutoCollapse(
        isHoverExpanded: true,
        isPanelHovered: false,
        hasPendingAutoCollapse: false,
        suppressionExpiresAt: Date(timeIntervalSince1970: 99),
        now: Date(timeIntervalSince1970: 100)
    ))
    #expect(DesktopFloatingHoverBehavior.isCurrentAutoCollapseRequest(
        firedRequestID: 8,
        currentRequestID: 8
    ))
    #expect(!DesktopFloatingHoverBehavior.isCurrentAutoCollapseRequest(
        firedRequestID: 8,
        currentRequestID: 9
    ))
    let now = Date(timeIntervalSince1970: 100)
    #expect(DesktopFloatingHoverBehavior.autoCollapseDelay(
        expandedAt: now,
        now: now
    ) == 0.75)
    #expect(DesktopFloatingHoverBehavior.autoCollapseDelay(
        expandedAt: now.addingTimeInterval(-1),
        now: now
    ) == 0.25)
}

@Test func completionReminderBuildsASixSecondSummaryCapsule() {
    let now = Date(timeIntervalSince1970: 100)
    let running = WorkItem(
        id: "codex:1",
        source: "Codex",
        title: "分析任务",
        status: .running,
        updatedAt: now
    )
    let waiting = WorkItem(
        id: "codex:1",
        source: "Codex",
        title: "分析任务",
        status: .waiting,
        updatedAt: now.addingTimeInterval(1)
    )
    let previous = WorkStatusSnapshot(items: [running], automationIssues: [], refreshedAt: now)
    let current = WorkStatusSnapshot(items: [waiting], automationIssues: [], refreshedAt: now)

    #expect(DesktopCompletionReminderBehavior.revealDuration == 6)
    #expect(DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
        previous: previous,
        current: current
    ) == ["codex:1"])
    #expect(DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
        previous: nil,
        current: current
    ).isEmpty)
    #expect(DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
        previous: current,
        current: current
    ).isEmpty)
    #expect(DesktopCompletionReminderBehavior.completedItem(
        previous: previous,
        current: current,
        matching: ["codex:1"]
    )?.displayTitle == "分析任务")

    let disappeared = WorkStatusSnapshot(items: [], automationIssues: [], refreshedAt: now)
    #expect(DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
        previous: previous,
        current: disappeared
    ) == ["codex:1"])
    #expect(DesktopCompletionReminderBehavior.completedItem(
        previous: previous,
        current: disappeared,
        matching: ["codex:1"]
    )?.displayTitle == "分析任务")

    let runningAutomation = WorkItem(
        id: "automation:1",
        source: "Automation",
        title: "定时任务",
        status: .running,
        updatedAt: now
    )
    #expect(DesktopCompletionReminderBehavior.newlyCompletedItemIDs(
        previous: WorkStatusSnapshot(items: [runningAutomation], automationIssues: []),
        current: disappeared
    ).isEmpty)
    let completion = DesktopFloatingButtonPresentation.completion(
        item: running,
        result: "已完成资料核对"
    )
    #expect(completion.displayText == "分析任务")
    #expect(completion.detailText == "已完成资料核对")
    #expect(completion.tintColor == .systemGreen)
}

@MainActor
@Test func clickingTheCapsuleUsesTheSameAutoCollapseLifecycleAsHovering() {
    let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
    var expansionAllowsAutoCollapse = false
    view.onActivate = { expansionAllowsAutoCollapse = true }

    view.handleActivate()

    #expect(expansionAllowsAutoCollapse)
    #expect(DesktopFloatingHoverBehavior.shouldAutoCollapse(
        isHoverExpanded: expansionAllowsAutoCollapse,
        isPanelHovered: false
    ))
}

@MainActor
@Test func explicitlyShowingThePanelReturnsToTheAutoCollapseLifecycle() {
    let controller = DesktopStatusPanelController()
    controller.showAutoCollapsing()

    #expect(controller.isWaitingForPointerLeaveToCollapse)
    controller.hide()
}

@MainActor
@Test func screenReconfigurationRestoresTheRequestedFrontmostWindow() {
    let controller = DesktopStatusPanelController()
    controller.setDisplayMode(.floating)

    controller.showCollapsed()
    controller.orderWindowsOutForTesting()
    controller.recoverAfterScreenConfigurationChange()
    #expect(controller.floatingPanelIsVisibleForTesting)
    #expect(!controller.panelIsVisibleForTesting)
    #expect(controller.floatingPanelLevelForTesting == .floating)

    controller.show()
    controller.orderWindowsOutForTesting()
    controller.recoverAfterScreenConfigurationChange()
    #expect(controller.panelIsVisibleForTesting)
    #expect(!controller.floatingPanelIsVisibleForTesting)
    #expect(controller.panelLevelForTesting == .floating)

    controller.hide()
}

@MainActor
@Test func screenReconfigurationDoesNotRevealAnIntentionallyHiddenWorkIsland() {
    let controller = DesktopStatusPanelController()
    controller.showCollapsed()
    controller.hide()

    controller.recoverAfterScreenConfigurationChange()

    #expect(!controller.panelIsVisibleForTesting)
    #expect(!controller.floatingPanelIsVisibleForTesting)
}

@Test func visibleCapsuleRepairsAStaleExpandedWindowState() {
    #expect(DesktopFloatingPanelTransition.shouldActivate(
        isMinimizedToFloatingButton: false,
        isFloatingPanelVisible: true
    ))
    #expect(DesktopFloatingPanelTransition.shouldActivate(
        isMinimizedToFloatingButton: false,
        isFloatingPanelVisible: true
    ))
    #expect(!DesktopFloatingPanelTransition.shouldActivate(
        isMinimizedToFloatingButton: false,
        isFloatingPanelVisible: false
    ))
}

@Test func hoverExpansionFloatsAboveAFullScreenWindowWithoutChangingTheSavedMode() {
    #expect(!DesktopPanelWindowPolicy.floatsAboveFullScreen(
        mode: .background,
        hoverExpanded: false
    ))
    #expect(DesktopPanelWindowPolicy.floatsAboveFullScreen(
        mode: .background,
        hoverExpanded: true
    ))
    #expect(DesktopPanelWindowPolicy.floatsAboveFullScreen(
        mode: .floating,
        hoverExpanded: false
    ))
}

@MainActor
@Test func floatingStatusButtonUsesRestrainedRunningAndTransitionAnimations() {
    let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
    view.layoutSubtreeIfNeeded()
    let runningItem = WorkItem(
        id: "running",
        source: "Codex",
        title: "克制动画",
        status: .running,
        updatedAt: Date()
    )

    view.update(snapshot: WorkStatusSnapshot(items: [runningItem], automationIssues: []))
    let motion = view.motionSnapshot()

    #expect(!motion.root.contains("statusBounce"))
    #expect(motion.root.contains("statusBorderFlash"))
    #expect(motion.root.contains("runningBorderPulse"))
    #expect(motion.statusDot.contains("statusPulse"))
    #expect(motion.statusDot.contains("statusDotPop"))
    #expect(motion.ripple.contains("runningRipple"))
    #expect(motion.ripple.contains("statusBurst"))
    #expect(!motion.ambient.contains("ambientDrift"))
    #expect(!motion.border.contains("borderOrbit"))
    #expect(!motion.sheen.contains("statusSheen"))

    view.update(snapshot: WorkStatusSnapshot(items: [], automationIssues: []))
    #expect(!view.motionSnapshot().root.contains("runningBorderPulse"))
}

@MainActor
@Test func completionCapsuleStagesReadableContentAfterItsShellBeginsMorphing() {
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.completionSize)
    )
    view.showCompletion(
        item: WorkItem(
            id: "codex:completion-motion",
            source: "Codex",
            title: "完成更新动效",
            status: .completed,
            updatedAt: Date()
        ),
        result: "排版与动画已更新"
    )

    let motion = view.motionSnapshot()
    #expect(motion.statusLabel.contains("completionOutgoingContentExit"))
    #expect(!motion.root.contains("statusBounce"))
}

@MainActor
@Test func completionCapsuleUsesOneAnchoredPathForExpansionAndCollapse() {
    let view = FloatingStatusButtonView(
        frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.completionSize)
    )
    view.showCompletion(
        item: WorkItem(
            id: "codex:completion-shell-motion",
            source: "Codex",
            title: "胶囊连续形变",
            status: .completed,
            updatedAt: Date()
        ),
        result: "展开和缩回共用右侧锚定路径"
    )
    view.prepareCompletionShellExpansion(
        from: DesktopFloatingButtonLayout.size,
        to: DesktopFloatingButtonLayout.completionSize
    )
    let preparedGeometry = view.completionShellMaskGeometryForTesting()
    #expect(preparedGeometry.position == CGPoint(
        x: DesktopFloatingButtonLayout.completionSize.width,
        y: DesktopFloatingButtonLayout.completionSize.height
    ))
    #expect(preparedGeometry.size == DesktopFloatingButtonLayout.size)
    #expect(preparedGeometry.cornerRadius == DesktopFloatingButtonLayout.cornerRadius)

    view.playPreparedCompletionShellExpansion()
    let expansionMotion = view.motionSnapshot()
    #expect(expansionMotion.shellMask.contains("completionShellMorph"))
    view.startCompletionMarqueeForTesting()
    #expect(view.motionSnapshot().border.contains("completionMarqueeOrbit"))
    #expect(view.completionMarqueeRepeatsForTesting())
    #expect(view.completionMarqueeOpacityForTesting() == 0.72)

    view.playCompletionShellCollapse(to: DesktopFloatingButtonLayout.size) {}
    let collapseMotion = view.motionSnapshot()
    #expect(collapseMotion.shellMask.contains("completionShellCollapse"))
    #expect(collapseMotion.statusLabel.contains("completionContentExit"))
    #expect(collapseMotion.detailLabel.contains("completionContentExit"))
}

@Test func completionMorphEndsAtTheCompactCapsulesFinalTopRightPosition() {
    let expandedBounds = NSRect(
        origin: .zero,
        size: DesktopFloatingButtonLayout.completionSize
    )
    let compactRect = DesktopFloatingButtonLayout.completionMorphCompactRect(
        in: expandedBounds
    )

    #expect(compactRect.maxX == expandedBounds.maxX)
    #expect(compactRect.maxY == expandedBounds.maxY)
    #expect(compactRect.size == DesktopFloatingButtonLayout.size)
    #expect(compactRect.minY != expandedBounds.midY - compactRect.height / 2)
}

@Test func completionContentLeavesOnlyAtTheEndOfTheCollapse() {
    #expect(DesktopFloatingButtonMotion.completionContentExitDuration == 0.10)
    #expect(
        DesktopFloatingButtonMotion.completionContentExitDuration
            < DesktopLiquidMotion.completionMorphCollapseDuration / 2
    )
}

@Test func dragHandleKeepsEnoughContrastOnLightBackgrounds() {
    let lightIdle = DesktopLiquidGlassTokens.dragHandleAlpha(
        isDark: false,
        isHovering: false,
        isPressed: false
    )
    let lightHover = DesktopLiquidGlassTokens.dragHandleAlpha(
        isDark: false,
        isHovering: true,
        isPressed: false
    )
    let lightPressed = DesktopLiquidGlassTokens.dragHandleAlpha(
        isDark: false,
        isHovering: true,
        isPressed: true
    )

    #expect(lightIdle >= 0.45)
    #expect(lightIdle < lightHover)
    #expect(lightHover < lightPressed)
    #expect(
        DesktopLiquidGlassTokens.dragHandleAlpha(
            isDark: true,
            isHovering: false,
            isPressed: false
        ) >= 0.30
    )
}

@MainActor
@Test func dragHandleTravelsWithTheCompletionCapsuleCenter() {
    let handle = FloatingDragHandleView(frame: NSRect(
        origin: .zero,
        size: DesktopFloatingButtonLayout.dragHandleSize
    ))
    let travel = (
        DesktopFloatingButtonLayout.completionSize.width
            - DesktopFloatingButtonLayout.size.width
    ) / 2
    handle.playCompletionExpansion(
        horizontalTravel: travel,
        duration: DesktopLiquidMotion.morphDuration
    )
    #expect(handle.completionMotionKeysForTesting.contains("completionHandleExpansion"))

    handle.playCompletionCollapse(
        horizontalTravel: travel,
        duration: DesktopLiquidMotion.completionMorphCollapseDuration
    )
    #expect(handle.completionMotionKeysForTesting.contains("completionHandleCollapse"))
}

@Test func desktopPanelIgnoresRefreshOnlyChangesButDetectsVisibleContentChanges() {
    let firstItem = WorkItem(
        id: "codex:1",
        source: "Codex",
        title: "分析任务",
        detail: "正在处理",
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 100)
    )
    let refreshedItem = WorkItem(
        id: "codex:1",
        source: "Codex",
        title: "分析任务",
        detail: "正在处理",
        status: .running,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let changedItem = WorkItem(
        id: "codex:1",
        source: "Codex",
        title: "分析任务",
        detail: "等待查看",
        status: .waiting,
        updatedAt: Date(timeIntervalSince1970: 200)
    )
    let tokens = ["section:active:true", "codex:1"]

    let first = DesktopPanelContentSignature(
        snapshot: WorkStatusSnapshot(items: [firstItem], automationIssues: []),
        layoutTokens: tokens,
        codexResults: ["codex:1": "上轮完成"]
    )
    let refreshOnly = DesktopPanelContentSignature(
        snapshot: WorkStatusSnapshot(items: [refreshedItem], automationIssues: []),
        layoutTokens: tokens,
        codexResults: ["codex:1": "上轮完成"]
    )
    let resultChanged = DesktopPanelContentSignature(
        snapshot: WorkStatusSnapshot(items: [refreshedItem], automationIssues: []),
        layoutTokens: tokens,
        codexResults: ["codex:1": "新的上轮结果"]
    )
    let changed = DesktopPanelContentSignature(
        snapshot: WorkStatusSnapshot(items: [changedItem], automationIssues: []),
        layoutTokens: ["section:needsUser:true", "codex:1"],
        codexResults: ["codex:1": "不同结果"]
    )

    #expect(first == refreshOnly)
    #expect(first != resultChanged)
    #expect(first != changed)
}

@MainActor
@Test func taskStatusUsesTheReservedDashboardWidthAndHidesZeroStates() {
    let status = TaskStatusView()
    status.update(processing: 3, unread: 0)
    status.layoutSubtreeIfNeeded()
    #expect(status.fittingSize.width == 156)
    #expect(status.fittingSize.height == 30)
    #expect(status.accessibilityLabel() == "处理中 3")

    status.update(processing: 0, unread: 1)
    #expect(status.accessibilityLabel() == "待读 1")
}

@Test func effortChoicesMatchAllCodexReasoningSteps() {
    #expect(EffortChoice.allCases.map(\.rawValue) == [
        "low",
        "medium",
        "high",
        "xhigh",
        "max",
        "ultra",
    ])
    #expect(EffortChoice.commandOptionCount == 6)
    #expect(EffortChoice.ultra.commandTargetIndex == 5)
    #expect(EffortChoice.allCases.map(\.shortTitle) == ["低", "中", "高", "极高", "Max", "Ultra"])
    #expect(EffortChoice.low.accessibilityLabels.contains("轻度"))
    #expect(EffortChoice.medium.accessibilityLabels.contains("中度"))
    #expect(EffortChoice.high.accessibilityLabels.contains("高度"))
    #expect(EffortChoice.xhigh.accessibilityLabels.contains("极高"))
}

@Test func waitingForUserSectionIsAlwaysExpandedAndShownFirst() {
    #expect(WorkSection.allCases.first == .needsUser)
    #expect(WorkSection.needsUser.isAlwaysExpanded)
    #expect(!WorkSection.active.isAlwaysExpanded)
    #expect(!WorkSection.queued.isAlwaysExpanded)
    #expect(!WorkSection.recent.isAlwaysExpanded)
}

@Test func activeSectionIsTheDefaultCollapsibleSection() {
    #expect(WorkSection.defaultExpandedSections == [.active])
    #expect(WorkSection.defaultExpandedSections.contains(.active))
    #expect(!WorkSection.defaultExpandedSections.contains(.recent))
    #expect(!WorkSection.defaultExpandedSections.contains(.queued))
}

@MainActor
@Test func panelControlsActOnTheClickThatActivatesTheWindow() {
    #expect(FirstMouseButton().acceptsFirstMouse(for: nil))
    #expect(PastedImageTextField().acceptsFirstMouse(for: nil))
}

@MainActor
@Test func panelBackgroundTracksEveryLiveResizeFrameWithoutDeferredGeometryAnimation() {
    let view = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    let liveResizeSizes = [
        NSSize(width: 512, height: 366),
        NSSize(width: 606, height: 478),
        NSSize(width: 720, height: 640),
    ]

    for size in liveResizeSizes {
        view.setFrameSize(size)
        view.layoutSubtreeIfNeeded()
        #expect(view.surfaceHighlightFrameForTesting == CGRect(origin: .zero, size: size))
        #expect(view.surfaceHighlightAnimationKeysForTesting.isEmpty)
    }
}

@MainActor
@Test func liquidGlassUsesTheDesktopBehindThePanelAndPreservesReadableDepth() {
    let view = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    #expect(view.blendingMode == .behindWindow)

    for isDark in [false, true] {
        let panel = DesktopLiquidGlassTokens.panelBaseAlpha(isDark: isDark)
        let card = DesktopLiquidGlassTokens.cardAlpha(isDark: isDark, isHovering: false)
        let hoveredCard = DesktopLiquidGlassTokens.cardAlpha(isDark: isDark, isHovering: true)
        let input = DesktopLiquidGlassTokens.inputAlpha(isDark: isDark)
        let statusCapsule = DesktopLiquidGlassTokens.statusCapsuleFillAlpha(isDark: isDark)
        #expect(panel < card)
        #expect(card < input)
        #expect(card < hoveredCard)
        #expect(hoveredCard < 0.80)
        #expect(statusCapsule == (isDark ? 0.28 : 0.24))
    }
}

@Test func emptyWaitingCardArrowOpensTheThread() {
    #expect(CodexCardPrimaryActionPolicy.opensThreadWhenPromptIsEmpty(status: .waiting))
    #expect(!CodexCardPrimaryActionPolicy.opensThreadWhenPromptIsEmpty(status: .running))
}
