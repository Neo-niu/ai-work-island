import Testing
@testable import CodexTouchBar

struct AppVersionComparatorTests {
    @Test func comparesSemanticVersionComponentsNumerically() {
        #expect(AppVersionComparator.isNewer("v0.5.18", than: "0.5.17"))
        #expect(AppVersionComparator.isNewer("1.0.0", than: "0.9.99"))
        #expect(!AppVersionComparator.isNewer("0.5.17", than: "0.5.17"))
        #expect(!AppVersionComparator.isNewer("0.5.9", than: "0.5.10"))
    }

    @Test func toleratesMissingComponentsAndPrereleaseSuffixes() {
        #expect(AppVersionComparator.isNewer("v1.2.1", than: "1.2"))
        #expect(!AppVersionComparator.isNewer("1.2.0", than: "1.2"))
        #expect(AppVersionComparator.isNewer("2.0.0-beta.1", than: "1.9.9"))
    }

    @Test func acceptsTheExistingDateBasedReleaseConventionWithoutSelfPrompting() {
        #expect(!AppVersionComparator.isReleaseNewer(
            tag: "v2026.08.13",
            than: "0.5.17",
            bundledReleaseTag: "v2026.08.13"
        ))
        #expect(AppVersionComparator.isReleaseNewer(
            tag: "v2026.08.14",
            than: "0.5.17",
            bundledReleaseTag: "v2026.08.13"
        ))
    }
}
