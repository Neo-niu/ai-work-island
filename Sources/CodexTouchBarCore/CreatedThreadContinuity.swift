import Foundation

public struct PendingCreatedThread: Equatable, Sendable {
    public let thread: ActiveThread
    public let expiresAt: Date

    public init(thread: ActiveThread, expiresAt: Date) {
        self.thread = thread
        self.expiresAt = expiresAt
    }
}

public enum CreatedThreadContinuity {
    public static func reconcile(
        scannedThreads: [ActiveThread],
        pending: [String: PendingCreatedThread],
        now: Date = Date()
    ) -> (threads: [ActiveThread], pending: [String: PendingCreatedThread]) {
        let scannedByID = Dictionary(uniqueKeysWithValues: scannedThreads.map { ($0.id, $0) })
        var remaining: [String: PendingCreatedThread] = [:]
        var threads = scannedThreads

        for (threadID, entry) in pending where entry.expiresAt > now {
            if let scanned = scannedByID[threadID] {
                // Keep the fallback while the authoritative source still says the
                // turn is active. This bridges a later active-to-unread scan gap.
                if scanned.isActive {
                    remaining[threadID] = entry
                }
            } else {
                threads.append(entry.thread)
                remaining[threadID] = entry
            }
        }
        return (threads, remaining)
    }
}
