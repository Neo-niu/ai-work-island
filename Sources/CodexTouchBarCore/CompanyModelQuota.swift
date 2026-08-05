import Foundation

public struct CompanyModelQuota: Equatable, Sendable {
    public let totalUSD: Double
    public let usedUSD: Double
    public let resetsAt: Date?

    public init(totalUSD: Double, usedUSD: Double, resetsAt: Date?) {
        self.totalUSD = totalUSD
        self.usedUSD = usedUSD
        self.resetsAt = resetsAt
    }

    public var remainingUSD: Double { max(totalUSD - usedUSD, 0) }

    public var remainingPercent: Int {
        guard totalUSD > 0 else { return 0 }
        return Int((remainingUSD / totalUSD * 100).rounded())
    }

    public static func parsePlatformResponse(_ data: Data) -> CompanyModelQuota? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["success"] as? Bool == true,
              let payload = root["data"] as? [String: Any],
              let rawQuota = number(payload["period_quota"]),
              let rawUsed = number(payload["period_used_quota"]),
              rawQuota > 0 else {
            return nil
        }

        // ModelGate stores quota in 1 / 500,000 USD units.
        let quotaUnit = 500_000.0
        let reset = (payload["next_reset_at"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return CompanyModelQuota(
            totalUSD: rawQuota / quotaUnit,
            usedUSD: rawUsed / quotaUnit,
            resetsAt: reset
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}
