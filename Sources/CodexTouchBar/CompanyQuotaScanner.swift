import CodexTouchBarCore
import Foundation

actor CompanyQuotaScanner {
    private var cachedQuota: CompanyModelQuota?
    private var lastAttempt: Date?
    private let refreshInterval: TimeInterval = 60

    func scanIfNeeded(now: Date = Date()) async -> CompanyModelQuota? {
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < refreshInterval {
            return cachedQuota
        }
        lastAttempt = now
        cachedQuota = await readThroughEdge()
        return cachedQuota
    }

    private func readThroughEdge() async -> CompanyModelQuota? {
        await Task.detached(priority: .utility) {
            let source = """
            tell application "Microsoft Edge"
                repeat with browserWindow in windows
                    repeat with browserTab in tabs of browserWindow
                        if URL of browserTab starts with "https://model.zhenguanyu.com/" then
                            return execute browserTab javascript "(()=>{const x=new XMLHttpRequest();x.open('GET','/api/v1/users/self',false);x.send();return x.responseText})()"
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else { return nil }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return CompanyModelQuota.parsePlatformResponse(data)
            } catch {
                return nil
            }
        }.value
    }
}
