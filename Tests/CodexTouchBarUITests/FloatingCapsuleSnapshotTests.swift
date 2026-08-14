import AppKit
@testable import CodexTouchBar
import CodexTouchBarCore
import Foundation
import Testing

@MainActor
@Suite("Floating capsule visual regression")
struct FloatingCapsuleSnapshotTests {
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func twentyCriticalCapsuleStates() throws {
        let cases: [(String, () -> FloatingStatusButtonView)] = [
            ("01-idle", { self.makeView(items: []) }),
            ("02-running-one", { self.makeView(items: [self.item(.running)]) }),
            ("03-running-two", { self.makeView(items: [self.item(.running, id: "a"), self.item(.running, id: "b")]) }),
            ("04-queued", { self.makeView(items: [self.item(.queued)]) }),
            ("05-waiting", { self.makeView(items: [self.item(.waiting)]) }),
            ("06-failed", { self.makeView(items: [self.item(.failed)]) }),
            ("07-stale", { self.makeView(items: [self.item(.stale)]) }),
            ("08-completed", { self.makeView(items: [self.item(.completed, id: "codex:done")]) }),
            ("09-waiting-two", { self.makeView(items: [self.item(.waiting, id: "a"), self.item(.waiting, id: "b")]) }),
            ("10-failed-over-running", { self.makeView(items: [self.item(.running, id: "run"), self.item(.failed, id: "fail")]) }),
            ("11-company-configured", { self.makeQuotaView(companyUsed: 5, companyTotal: 20, page: 1) }),
            ("12-company-low", { self.makeQuotaView(companyUsed: 18, companyTotal: 20, page: 1) }),
            ("13-five-hour-healthy", { self.makeQuotaView(shortUsed: 29, page: 2) }),
            ("14-five-hour-warning", { self.makeQuotaView(shortUsed: 55, page: 2) }),
            ("15-five-hour-critical", { self.makeQuotaView(shortUsed: 82, page: 2) }),
            ("16-week-healthy", { self.makeQuotaView(weeklyUsed: 18, page: 2) }),
            ("17-week-warning", { self.makeQuotaView(weeklyUsed: 58, page: 2) }),
            ("18-week-critical", { self.makeQuotaView(weeklyUsed: 86, page: 2) }),
            ("19-recording", { self.makeRecordingView(phase: .recording) }),
            ("20-silence", { self.makeRecordingView(phase: .silence) }),
        ]

        for (name, factory) in cases {
            let view = factory()
            try assertVisualSnapshot(of: view, named: name)
        }
    }

    private func makeView(items: [WorkItem]) -> FloatingStatusButtonView {
        let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
        view.appearance = NSAppearance(named: .darkAqua)
        view.update(snapshot: WorkStatusSnapshot(items: items, automationIssues: [], refreshedAt: fixedNow))
        settle(view)
        return view
    }

    private func makeQuotaView(
        companyUsed: Double? = nil,
        companyTotal: Double? = nil,
        shortUsed: Double? = nil,
        weeklyUsed: Double? = nil,
        page: Int
    ) -> FloatingStatusButtonView {
        let company = companyUsed.flatMap { used in
            companyTotal.map { CompanyModelQuota(totalUSD: $0, usedUSD: used, resetsAt: nil) }
        }
        let view = FloatingStatusButtonView(frame: NSRect(origin: .zero, size: DesktopFloatingButtonLayout.size))
        view.appearance = NSAppearance(named: .darkAqua)
        view.update(snapshot: WorkStatusSnapshot(
            items: [],
            automationIssues: [],
            codexShortTermLimit: shortUsed.map { WeeklyLimitUsage(usedPercent: $0, resetsAt: nil, recordedAt: fixedNow) },
            codexWeeklyLimit: weeklyUsed.map { WeeklyLimitUsage(usedPercent: $0, resetsAt: nil, recordedAt: fixedNow) },
            companyQuota: company,
            refreshedAt: fixedNow
        ))
        for _ in 0..<page { view.advanceCarousel() }
        settle(view)
        return view
    }

    private func makeRecordingView(phase: VoiceMemoGuardianState.Phase) -> FloatingStatusButtonView {
        let view = makeView(items: [])
        view.updateRecordingGuardian(VoiceMemoGuardianState(
            phase: phase,
            startedAt: Date().addingTimeInterval(-8 * 60),
            silentSince: phase == .silence ? Date().addingTimeInterval(-6 * 60) : nil
        ))
        settle(view)
        return view
    }

    private func item(_ status: WorkItemStatus, id: String = "item") -> WorkItem {
        WorkItem(
            id: id,
            source: "test",
            title: "状态测试",
            status: status,
            updatedAt: fixedNow,
            outputPath: status == .completed ? "/tmp/result" : nil
        )
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        view.layer?.removeAllAnimations()
        view.layer?.sublayers?.forEach { $0.removeAllAnimations() }
    }

    private func assertVisualSnapshot(of view: NSView, named name: String) throws {
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            Issue.record("Could not allocate bitmap for \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let actual = representation.representation(using: .png, properties: [:]) else {
            Issue.record("Could not encode PNG for \(name)")
            return
        }

        let snapshotDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("__Snapshots__/FloatingCapsule", isDirectory: true)
        let baselineURL = snapshotDirectory.appendingPathComponent("\(name).png")
        let records = ProcessInfo.processInfo.environment["RECORD_VISUAL_SNAPSHOTS"] == "1"
        if records || !FileManager.default.fileExists(atPath: baselineURL.path) {
            try FileManager.default.createDirectory(
                at: snapshotDirectory,
                withIntermediateDirectories: true
            )
            try actual.write(to: baselineURL, options: .atomic)
            if !records {
                Issue.record("Recorded missing visual baseline: \(baselineURL.path)")
            }
            return
        }

        let expected = try Data(contentsOf: baselineURL)
        #expect(actual == expected, "Visual snapshot changed: \(name)")
    }
}
