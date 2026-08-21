import AppKit
import CodexTouchBarCore
import Foundation
import ScriptingBridge

actor CompanyQuotaScanner {
    private static let cachedQuotaDefaultsKey = "companyQuota.lastSuccessfulResponse"
    private var cachedQuota: CompanyModelQuota?
    private var lastAttempt: Date?
    private let refreshInterval = RefreshPolicy.companyQuotaInterval

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cachedQuotaDefaultsKey) {
            cachedQuota = try? JSONDecoder().decode(CompanyModelQuota.self, from: data)
        }
    }

    func scanIfNeeded(now: Date = Date()) async -> CompanyModelQuota? {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < refreshInterval {
            return cachedQuota
        }
        lastAttempt = now
        if let refreshedQuota = await readThroughEdge() {
            cachedQuota = refreshedQuota
            if let data = try? JSONEncoder().encode(refreshedQuota) {
                UserDefaults.standard.set(data, forKey: Self.cachedQuotaDefaultsKey)
            }
        }
        return cachedQuota
    }

    private func readThroughEdge() async -> CompanyModelQuota? {
        await Task.detached(priority: .utility) {
            let edgeApplications = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.microsoft.edgemac"
            ).filter { $0.activationPolicy == .regular && !$0.isTerminated }
            for edgeApplication in edgeApplications {
                guard let application = SBApplication(
                    processIdentifier: edgeApplication.processIdentifier
                ),
                let windows = (application as NSObject).value(forKey: "windows") as? SBElementArray else {
                    continue
                }
                for case let window as NSObject in windows {
                    guard let tabs = window.value(forKey: "tabs") as? SBElementArray else { continue }
                    for case let tab as NSObject in tabs {
                        let url = tab.value(forKey: "URL") as? String
                        guard url?.hasPrefix("https://model.zhenguanyu.com/") == true else { continue }
                        let javascript = """
                        (()=>{
                          const x=new XMLHttpRequest();
                          const nonce=Date.now();
                          x.open('GET',`/api/v1/users/self?_work_island_refresh=${nonce}`,false);
                          x.setRequestHeader('Cache-Control','no-cache');
                          x.send();
                          return x.responseText;
                        })()
                        """
                        if let quota = Self.execute(javascript, in: tab) { return quota }
                        // Edge may discard a background tab. Reloading the exact
                        // company page wakes it without selecting it, then retry.
                        _ = tab.perform(NSSelectorFromString("reload"))
                        try? await Task.sleep(for: .seconds(1.5))
                        if let quota = Self.execute(javascript, in: tab) { return quota }
                    }
                }
            }
            return nil
        }.value
    }

    nonisolated private static func execute(_ javascript: String, in tab: NSObject) -> CompanyModelQuota? {
        guard let response = tab.perform(
            NSSelectorFromString("executeJavascript:"),
            with: javascript
        )?.takeUnretainedValue() as? String else { return nil }
        return CompanyModelQuota.parsePlatformResponse(Data(response.utf8))
    }
}
