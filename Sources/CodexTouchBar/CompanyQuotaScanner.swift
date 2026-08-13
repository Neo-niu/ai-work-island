import AppKit
import CodexTouchBarCore
import Foundation
import ScriptingBridge

actor CompanyQuotaScanner {
    private var cachedQuota: CompanyModelQuota?
    private var lastAttempt: Date?
    private let refreshInterval: TimeInterval = 60

    func scanIfNeeded(now: Date = Date()) async -> CompanyModelQuota? {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < refreshInterval {
            return cachedQuota
        }
        lastAttempt = now
        if let refreshedQuota = await readThroughEdge() {
            cachedQuota = refreshedQuota
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
                        (()=>{const x=new XMLHttpRequest();x.open('GET','/api/v1/users/self',false);x.send();return x.responseText})()
                        """
                        guard let response = tab.perform(
                            NSSelectorFromString("executeJavascript:"),
                            with: javascript
                        )?.takeUnretainedValue() as? String else { continue }
                        return CompanyModelQuota.parsePlatformResponse(Data(response.utf8))
                    }
                }
            }
            return nil
        }.value
    }
}
