import Testing
@testable import BunnyCore

struct VersionRulesTests {
    @Test func newerPatchAndMinor() {
        #expect(VersionRules.isNewer("3.0.1", than: "3.0.0"))
        #expect(!VersionRules.isNewer("3.0.0", than: "3.0.1"))
        #expect(VersionRules.isNewer("3.1.0", than: "3.0.9"))
        #expect(!VersionRules.isNewer("3.0.9", than: "3.1.0"))
        #expect(VersionRules.isNewer("3.0.10", than: "3.0.9"))
        #expect(VersionRules.isNewer("4.0.0", than: "3.9.9"))
    }

    @Test func equalIsNotNewer() {
        #expect(!VersionRules.isNewer("3.0.0", than: "3.0.0"))
        #expect(!VersionRules.isNewer("3.0", than: "3.0.0"))
        #expect(!VersionRules.isNewer("3.0.0", than: "3"))
        #expect(VersionRules.isNewer("3.0.1", than: "3.0"))
    }

    @Test func leadingVIsStripped() {
        #expect(VersionRules.isNewer("v3.0.1", than: "3.0.0"))
        #expect(VersionRules.isNewer("V3.0.1", than: "v3.0.0"))
        #expect(VersionRules.display("v3.0.1") == "3.0.1")
        #expect(VersionRules.display(" 3.0.1 ") == "3.0.1")
    }

    @Test func nonNumericTagsAreNeverNewer() {
        for tag in ["alpha", "beta", "", "v", "3.1.0-beta", "3.1.0-beta.1", "3..1", "3.x", "-1.0", "latest"] {
            #expect(!VersionRules.isNewer(tag, than: "3.0.0"), "\(tag)")
        }
        // An unreadable current version never claims an update either.
        #expect(!VersionRules.isNewer("3.0.1", than: "—"))
    }
}
