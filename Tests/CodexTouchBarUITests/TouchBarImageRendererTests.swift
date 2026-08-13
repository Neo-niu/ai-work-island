import AppKit
@testable import CodexTouchBar
import CodexTouchBarCore
import Testing

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
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 0).width == 372)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 1).width == 372)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 7).width == 372)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 7).height == 618)
    #expect(DesktopPanelLayout.contentSize(visibleItemCount: 7, sectionCount: 4).height == 700)
}

@Test func conversationCardUsesTheAvailablePanelWidth() {
    #expect(DesktopPanelLayout.contentWidth == 344)
    #expect(DesktopPanelLayout.conversationContentWidth == 322)
}

@Test func conversationCardReservesTwoLineStatusHeight() {
    let withoutConversation = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1
    )
    let withConversation = DesktopPanelLayout.contentSize(
        visibleItemCount: 1,
        sectionCount: 1,
        conversationItemCount: 1
    )

    #expect(withConversation.height - withoutConversation.height == 54)
}

@Test func detailedModeReservesReadableConversationSpace() {
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

    #expect(DesktopContentMode.clean.title == "清爽模式")
    #expect(DesktopContentMode.detailed.title == "详细模式")
    #expect(DesktopContentMode.detailed.conversationStatusLineCount == 4)
    #expect(withConversation.height - withoutConversation.height == 86)
}

@Test func contentDensityModesKeepTheirCardMetricsAndBoundedPanelHeight() {
    #expect(DesktopContentMode.clean.conversationCardHeight == 116)
    #expect(DesktopContentMode.clean.conversationExtraHeight == 54)
    #expect(DesktopContentMode.clean.conversationStatusLineCount == 2)
    #expect(DesktopContentMode.clean.conversationStatusFontSize == 10)
    #expect(DesktopContentMode.detailed.conversationCardHeight == 148)
    #expect(DesktopContentMode.detailed.conversationExtraHeight == 86)
    #expect(DesktopContentMode.detailed.conversationStatusFontSize == 11.5)

    #expect(DesktopPanelLayout.contentSize(
        visibleItemCount: 7,
        sectionCount: 4,
        conversationItemCount: 7,
        contentMode: .clean
    ).height == 700)
    #expect(DesktopPanelLayout.contentSize(
        visibleItemCount: 7,
        sectionCount: 4,
        conversationItemCount: 7,
        contentMode: .detailed
    ).height == 720)
}

@Test func desktopPanelResizePolicyAllowsAUsefulWidthAndHeightRange() {
    #expect(DesktopPanelResizePolicy.minimumFrameSize == NSSize(width: 320, height: 260))
    #expect(DesktopPanelResizePolicy.maximumFrameSize == NSSize(width: 620, height: 746))
    #expect(
        DesktopPanelResizePolicy.clampedFrameSize(NSSize(width: 280, height: 900))
            == NSSize(width: 320, height: 746)
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

@Test func desktopPanelUsesTheSelectedSmokeGrayPalette() {
    let base = DesktopPanelPalette.base.usingColorSpace(.sRGB)
    let card = DesktopPanelPalette.card.usingColorSpace(.sRGB)
    let input = DesktopPanelPalette.input.usingColorSpace(.sRGB)

    #expect(base?.redComponent == 48.0 / 255.0)
    #expect(base?.greenComponent == 50.0 / 255.0)
    #expect(base?.blueComponent == 55.0 / 255.0)
    #expect(card?.redComponent == 58.0 / 255.0)
    #expect(input?.redComponent == 39.0 / 255.0)
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
    #expect(DesktopFloatingButtonLayout.canvasSize == NSSize(width: 120, height: 50))
    #expect(DesktopFloatingButtonLayout.animationInset == 6)
    #expect(DesktopFloatingButtonLayout.cornerRadius == 19)
    #expect(DesktopFloatingButtonLayout.statusDotSize == 8)
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

@Test func expandedPanelAndCollapsedPillShareTheSameTopRightAnchor() {
    let floatingFrame = NSRect(x: 1_320, y: 840, width: 120, height: 50)
    let panelFrame = DesktopPanelAnchorLayout.panelFrame(
        anchoredToFloatingPanel: floatingFrame,
        panelSize: NSSize(width: 372, height: 290)
    )
    #expect(panelFrame.maxX == floatingFrame.maxX)
    #expect(panelFrame.maxY == floatingFrame.maxY)

    let restoredFloatingFrame = DesktopPanelAnchorLayout.floatingFrame(
        anchoredToPanel: panelFrame,
        floatingSize: floatingFrame.size
    )
    #expect(restoredFloatingFrame == floatingFrame)
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
    #expect(waitingPresentation.displayText == "1 等待你")
    #expect(waitingPresentation.tintColor == .systemOrange)
    #expect(!waitingPresentation.pulses)
    #expect(completedPresentation.displayText == "已完成")
    #expect(completedPresentation.tintColor == .systemGreen)
    #expect(idlePresentation.displayText == "空闲")
    #expect(idlePresentation.tintColor == .secondaryLabelColor)
    #expect(activePresentation.accessibilityLabel == "恢复 AI 工作岛；当前1 运行")
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
    #expect(DesktopFloatingButtonMotion.entranceDuration >= 0.35)
    #expect(DesktopFloatingButtonMotion.transitionDuration >= 0.55)
    #expect(DesktopFloatingButtonMotion.ambientCycleDuration > DesktopFloatingButtonMotion.transitionDuration)
    #expect(DesktopFloatingButtonMotion.borderCycleDuration > 1)
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
        companyQuota: CompanyModelQuota(totalUSD: 20, usedUSD: 5, resetsAt: nil)
    )

    let pages = DesktopFloatingButtonPresentation.carousel(for: snapshot)

    #expect(pages.map(\.displayText) == ["空闲", "公司 $15", "5时 71%", "周 58%"])
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
    #expect(pages[0].accessibilityLabel == "恢复 AI 工作岛；当前1 需处理")
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
}

@Test func restoredPanelCannotBeHiddenByAStaleMinimizeAnimation() {
    #expect(DesktopFloatingPanelTransition.shouldFinishMinimizing(isMinimizedToFloatingButton: true))
    #expect(!DesktopFloatingPanelTransition.shouldFinishMinimizing(isMinimizedToFloatingButton: false))
}

@Test func hoverExpandedPanelCollapsesOnlyAfterThePointerLeaves() {
    #expect(DesktopFloatingHoverBehavior.collapseDelay == 0.5)
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
    #expect(DesktopFloatingHoverBehavior.isCurrentAutoCollapseRequest(
        firedRequestID: 8,
        currentRequestID: 8
    ))
    #expect(!DesktopFloatingHoverBehavior.isCurrentAutoCollapseRequest(
        firedRequestID: 8,
        currentRequestID: 9
    ))
}

@Test func completionReminderRevealsOnlyNewlyFinishedWorkForFourSeconds() {
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

    #expect(DesktopCompletionReminderBehavior.revealDuration == 4)
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
    #expect(DesktopCompletionReminderBehavior.autoCollapseDelay(
        standardDelay: 0.5,
        completionRevealRemaining: 3.8
    ) == 3.8)
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
@Test func floatingStatusButtonInstallsLayeredRunningAndTransitionAnimations() {
    let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
    view.layoutSubtreeIfNeeded()
    let runningItem = WorkItem(
        id: "running",
        source: "Codex",
        title: "丰富动画",
        status: .running,
        updatedAt: Date()
    )

    view.update(snapshot: WorkStatusSnapshot(items: [runningItem], automationIssues: []))
    let motion = view.motionSnapshot()

    #expect(motion.root.contains("statusBounce"))
    #expect(motion.root.contains("statusBorderFlash"))
    #expect(motion.statusDot.contains("statusPulse"))
    #expect(motion.statusDot.contains("statusDotPop"))
    #expect(motion.ripple.contains("runningRipple"))
    #expect(motion.ripple.contains("statusBurst"))
    #expect(motion.ambient.contains("ambientDrift"))
    #expect(motion.border.contains("borderOrbit"))
    #expect(motion.sheen.contains("statusSheen"))
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
    #expect(WorkSection.defaultExpandedSection(from: [.needsUser, .active, .recent]) == .active)
    #expect(WorkSection.defaultExpandedSection(from: [.needsUser, .queued, .recent]) == .queued)
    #expect(WorkSection.defaultExpandedSection(from: [.needsUser]) == nil)
}

@MainActor
@Test func panelControlsActOnTheClickThatActivatesTheWindow() {
    #expect(FirstMouseButton().acceptsFirstMouse(for: nil))
    #expect(PastedImageTextField().acceptsFirstMouse(for: nil))
}

@Test func emptyWaitingCardArrowOpensTheThread() {
    #expect(CodexCardPrimaryActionPolicy.opensThreadWhenPromptIsEmpty(status: .waiting))
    #expect(!CodexCardPrimaryActionPolicy.opensThreadWhenPromptIsEmpty(status: .running))
}
