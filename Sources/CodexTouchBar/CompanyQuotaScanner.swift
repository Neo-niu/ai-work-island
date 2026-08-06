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
        if let refreshedQuota = await readThroughEdge() {
            cachedQuota = refreshedQuota
        }
        return cachedQuota
    }

    private func readThroughEdge() async -> CompanyModelQuota? {
        await Task.detached(priority: .utility) {
            let source = """
            with timeout of 8 seconds
                tell application "Microsoft Edge"
                    repeat with browserWindow in windows
                        repeat with browserTab in tabs of browserWindow
                            if URL of browserTab starts with "https://model.zhenguanyu.com/" then
                                reload browserTab
                                delay 0.8
                                set responseText to execute browserTab javascript "(()=>{const x=new XMLHttpRequest();x.open('GET','/api/v1/users/self',false);x.send();return x.responseText})()"
                                return responseText
                            end if
                        end repeat
                    end repeat
                end tell
            end timeout
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
                for _ in 0..<100 where process.isRunning {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                if process.isRunning {
                    process.terminate()
                    process.waitUntilExit()
                    return nil
                }
                guard process.terminationStatus == 0 else { return nil }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                return CompanyModelQuota.parsePlatformResponse(data)
            } catch {
                return nil
            }
        }.value
    }
}
