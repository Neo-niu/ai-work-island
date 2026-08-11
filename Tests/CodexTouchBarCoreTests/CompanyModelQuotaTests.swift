import CodexTouchBarCore
import Foundation
import Testing

@Test func parsesCompanyModelPlatformQuota() throws {
    let data = Data(#"{"success":true,"data":{"period_quota":100000000,"period_used_quota":8041411,"next_reset_at":"2026-09-01T00:00:00Z"}}"#.utf8)
    let quota = try #require(CompanyModelQuota.parsePlatformResponse(data))
    #expect(quota.totalUSD == 200)
    #expect(abs(quota.usedUSD - 16.082822) < 0.000001)
    #expect(quota.remainingPercent == 92)
}

@Test func rejectsUnavailableCompanyQuota() {
    let data = Data(#"{"success":false,"error":"UNAUTHORIZED"}"#.utf8)
    #expect(CompanyModelQuota.parsePlatformResponse(data) == nil)
}
