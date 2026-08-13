import Foundation

enum IndependentAppRelauncher {
    static let launchLabel = "dev.kanyun.AIWorkIsland.Relauncher"

    static func launchctlArguments(bundlePath: String, currentPID: Int32) -> [String] {
        [
            "submit",
            "-l", launchLabel,
            "--",
            "/bin/sh",
            "-c",
            """
            old_pid="$1"
            bundle_path="$2"
            for _ in $(/usr/bin/seq 1 100); do
              if ! /bin/kill -0 "$old_pid" 2>/dev/null; then
                break
              fi
              /bin/sleep 0.1
            done
            /bin/sleep 0.3
            /usr/bin/open "$bundle_path"
            # A submitted launchd job is not one-shot by default. Remove it
            # after reopening the app or launchd will run it again repeatedly.
            /bin/launchctl remove \(launchLabel) >/dev/null 2>&1 || true
            """,
            "ai-work-island-relauncher",
            String(currentPID),
            bundlePath,
        ]
    }

    static func schedule(bundlePath: String, currentPID: Int32 = ProcessInfo.processInfo.processIdentifier) throws {
        removeExistingJob()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = launchctlArguments(bundlePath: bundlePath, currentPID: currentPID)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "AIWorkIslandRelauncher",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "无法创建独立重启任务"]
            )
        }
    }

    private static func removeExistingJob() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["remove", launchLabel]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
