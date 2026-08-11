import CodexTouchBarCore
import SwiftUI
import WidgetKit

private struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetStatusSnapshot
}

private struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: previewSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(StatusEntry(date: Date(), snapshot: loadSnapshot() ?? previewSnapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(
            date: Date(),
            snapshot: loadSnapshot() ?? WidgetStatusSnapshot(items: [], refreshedAt: .distantPast)
        )
        let interval = RefreshPolicy.widgetReloadInterval(items: entry.snapshot.items)
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(interval))))
    }

    private func loadSnapshot() -> WidgetStatusSnapshot? {
        try? WidgetSnapshotStore().read()
    }

    private var previewSnapshot: WidgetStatusSnapshot {
        WidgetStatusSnapshot(items: [
            WorkItem(
                id: "preview:codex",
                source: "Codex",
                title: "分析业务数据",
                detail: "正在核验关键指标",
                status: .running,
                startedAt: Date().addingTimeInterval(-12 * 60),
                updatedAt: Date()
            ),
            WorkItem(
                id: "preview:automation",
                source: "Mario 数据自动化",
                title: "下载数据并合并",
                detail: "等待下次运行",
                status: .idle,
                startedAt: Date().addingTimeInterval(-35 * 60),
                updatedAt: Date()
            ),
        ])
    }
}

private struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var visibleItems: [WorkItem] {
        Array(entry.snapshot.items.prefix(family == .systemLarge ? 4 : 3))
    }

    private var attentionCount: Int {
        entry.snapshot.items.filter { $0.status == .waiting || $0.status == .failed || $0.status == .stale }.count
    }

    private var latestOutput: String? {
        entry.snapshot.items
            .filter { $0.outputPath != nil }
            .max(by: { $0.updatedAt < $1.updatedAt })?
            .outputPath
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var freshness: SnapshotFreshness {
        let age = max(0, entry.date.timeIntervalSince(entry.snapshot.refreshedAt))
        let isRunning = entry.snapshot.items.contains { $0.status.isActiveWork }
        if isRunning {
            if age > 10 * 60 { return .stale }
            if age > 2 * 60 { return .delayed }
        } else {
            if age > 90 * 60 { return .stale }
            if age > 35 * 60 { return .delayed }
        }
        return .fresh
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            content
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetStatusConfiguration.statusURL)
        } else {
            content
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))
                .widgetURL(WidgetStatusConfiguration.statusURL)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(entry.snapshot.items.count)")
                        .font(.system(size: family == .systemLarge ? 34 : 24, weight: .bold, design: .rounded))
                    Text("AI 工作")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 8) {
                        Link(destination: WidgetStatusConfiguration.refreshURL) {
                            Image(systemName: "arrow.clockwise.circle.fill")
                                .foregroundStyle(.blue)
                        }
                        Link(destination: WidgetStatusConfiguration.recordURL) {
                            Label("录音", systemImage: "mic.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                        }
                    }
                    if freshness != .fresh {
                        Label(freshness.title, systemImage: freshness.systemImage)
                            .font(.caption2)
                            .foregroundStyle(freshness.color)
                    } else if attentionCount > 0 {
                        Label("\(attentionCount) 项待处理", systemImage: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Divider()

            if visibleItems.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    if freshness == .fresh {
                        Label("全部空闲", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Label(freshness.title, systemImage: freshness.systemImage)
                            .foregroundStyle(freshness.color)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(visibleItems) { item in
                    HStack(spacing: 9) {
                        Circle()
                            .stroke(item.status.color, lineWidth: 2)
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.displayTitle)
                                .font(.system(size: 13, weight: .medium))
                                .lineLimit(1)
                            if family == .systemLarge {
                                Text(item.displayDetail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(item.status.chineseTitle)
                                .font(.caption)
                                .foregroundStyle(item.status.color)
                            if let startedAt = item.startedAt,
                               item.status.isActiveWork || item.status == .waiting {
                                Text(startedAt, style: .timer)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if family == .systemLarge, let latestOutput {
                    Divider()
                    Label {
                        Text("最新产出：\(latestOutput)")
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "doc.badge.checkmark")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 3) {
                Text("更新于")
                Text(entry.snapshot.refreshedAt, style: .relative)
                Spacer()
                if freshness != .fresh {
                    Text("点击 ↻ 刷新")
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(freshness == .fresh ? Color.secondary.opacity(0.7) : freshness.color)
        }
        .padding(family == .systemLarge ? 18 : 14)
    }
}

private enum SnapshotFreshness {
    case fresh
    case delayed
    case stale

    var title: String {
        switch self {
        case .fresh: "已更新"
        case .delayed: "数据延迟"
        case .stale: "状态未更新"
        }
    }

    var systemImage: String {
        switch self {
        case .fresh: "checkmark.circle"
        case .delayed: "clock.badge.exclamationmark"
        case .stale: "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fresh: .secondary
        case .delayed: .orange
        case .stale: .red
        }
    }
}

private struct CodexStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStatusConfiguration.kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("AI 工作状态")
        .description("查看 Codex 与本地自动化程序的当前状态。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CodexStatusWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexStatusWidget()
    }
}

@_silgen_name("NSExtensionMain")
private func nsExtensionMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32

@main
@MainActor
private enum CodexStatusWidgetBootstrap {
    private static var didInitialize = false

    static func main() {
        // SwiftPM executables return after WidgetBundle.main() instead of entering
        // the app-extension host loop. NSExtensionMain re-enters this symbol once;
        // the guard keeps WidgetKit registration single-shot.
        guard !didInitialize else { return }
        didInitialize = true
        CodexStatusWidgetBundle.main()
        _ = nsExtensionMain(CommandLine.argc, CommandLine.unsafeArgv)
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

    var color: Color {
        switch self {
        case .running: .blue
        case .queued: .indigo
        case .waiting: .orange
        case .failed, .stale: .red
        case .completed: .green
        case .idle: .secondary
        }
    }
}
