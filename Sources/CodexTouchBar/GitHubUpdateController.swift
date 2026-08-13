import AppKit
import Foundation

enum AppVersionComparator {
    static func isReleaseNewer(
        tag: String,
        than currentVersion: String,
        bundledReleaseTag: String?
    ) -> Bool {
        if bundledReleaseTag == tag { return false }
        if isDateBasedTag(tag) { return bundledReleaseTag != nil }
        return isNewer(tag, than: currentVersion)
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let candidateParts = numericParts(candidate)
        let currentParts = numericParts(current)
        let count = max(candidateParts.count, currentParts.count)

        for index in 0..<count {
            let candidatePart = index < candidateParts.count ? candidateParts[index] : 0
            let currentPart = index < currentParts.count ? currentParts[index] : 0
            if candidatePart != currentPart { return candidatePart > currentPart }
        }
        return false
    }

    private static func numericParts(_ version: String) -> [Int] {
        version.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split(separator: ".")
            .map { component in
                Int(component.prefix(while: { $0.isNumber })) ?? 0
            }
    }

    private static func isDateBasedTag(_ tag: String) -> Bool {
        let value = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = value.split(separator: ".")
        return parts.count == 3 && parts[0].count == 4 && Int(parts[0]) != nil
    }
}

@MainActor
final class GitHubUpdateController {
    private struct Release: Decodable, Sendable {
        let tagName: String
        let name: String?
        let body: String?
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case body
            case htmlURL = "html_url"
        }
    }

    private let repository: String
    private let appName: String
    private let defaults: UserDefaults
    private let checkInterval: TimeInterval = 24 * 60 * 60
    private var checkTask: Task<Void, Never>?

    private var lastCheckKey: String { "githubUpdate.lastCheck.\(repository)" }
    private var skippedVersionKey: String { "githubUpdate.skippedVersion.\(repository)" }

    init(repository: String, appName: String, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.appName = appName
        self.defaults = defaults
    }

    func scheduleAutomaticCheck() {
        guard shouldRunAutomaticCheck else { return }
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await self?.check(manual: false)
        }
    }

    func checkManually() {
        checkTask?.cancel()
        checkTask = Task { [weak self] in
            await self?.check(manual: true)
        }
    }

    func cancel() {
        checkTask?.cancel()
        checkTask = nil
    }

    private var shouldRunAutomaticCheck: Bool {
        guard let lastCheck = defaults.object(forKey: lastCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(lastCheck) >= checkInterval
    }

    private func check(manual: Bool) async {
        do {
            let release = try await fetchLatestRelease()
            defaults.set(Date(), forKey: lastCheckKey)
            let currentVersion = Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0"
            let bundledReleaseTag = Bundle.main.object(
                forInfoDictionaryKey: "GitHubReleaseTag"
            ) as? String

            guard AppVersionComparator.isReleaseNewer(
                tag: release.tagName,
                than: currentVersion,
                bundledReleaseTag: bundledReleaseTag
            ) else {
                if manual { showUpToDate(version: currentVersion) }
                return
            }
            if !manual, defaults.string(forKey: skippedVersionKey) == release.tagName { return }
            showAvailable(release: release, currentVersion: currentVersion)
        } catch {
            if manual { showFailure(error) }
        }
    }

    private func fetchLatestRelease() async throws -> Release {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("\(appName)-update-checker", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    private func showAvailable(release: Release, currentVersion: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "\(appName)有新版本 \(release.tagName)"
        let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        alert.informativeText = notes.isEmpty
            ? "当前版本：\(currentVersion)"
            : "当前版本：\(currentVersion)\n\n\(String(notes.prefix(800)))"
        alert.addButton(withTitle: "查看并下载")
        alert.addButton(withTitle: "稍后提醒")
        alert.addButton(withTitle: "跳过此版本")
        activateApplication()

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        case .alertThirdButtonReturn:
            defaults.set(release.tagName, forKey: skippedVersionKey)
        default:
            break
        }
    }

    private func showUpToDate(version: String) {
        let alert = NSAlert()
        alert.messageText = "\(appName)已是最新版"
        alert.informativeText = "当前版本：\(version)"
        alert.addButton(withTitle: "好")
        activateApplication()
        alert.runModal()
    }

    private func showFailure(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "暂时无法检查更新"
        alert.informativeText = "请检查网络后重试。\n\(error.localizedDescription)"
        alert.addButton(withTitle: "好")
        activateApplication()
        alert.runModal()
    }

    private func activateApplication() {
        if #available(macOS 14.0, *) {
            NSRunningApplication.current.activate()
        } else {
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        }
    }
}
