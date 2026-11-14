import Foundation
import Testing
@testable import BunnyCore

struct SettingsResetTests {
    @Test func removesEverythingButTheKeepList() {
        let stored: [String: Any] = [
            "appearance": "dark",
            "agent.claude.enabled": true,
            "agent.recentFolders": ["/tmp/a"],
            "onboarding.completed": true,
            "NSWindow Frame BunnySettings": "0 0 700 500",
        ]
        let keys = SettingsReset.keysToRemove(from: stored, keeping: ["onboarding.completed", "NSWindow Frame BunnySettings", "absent"])
        #expect(keys == ["agent.claude.enabled", "agent.recentFolders", "appearance"])
    }

    @Test func emptyKeepListRemovesAllAndEmptyDomainRemovesNothing() {
        #expect(SettingsReset.keysToRemove(from: ["b": 1, "a": 2], keeping: []) == ["a", "b"])
        #expect(SettingsReset.keysToRemove(from: [:], keeping: ["a"]).isEmpty)
    }

    /// Applied to a stored domain: the kept keys survive, the rest are gone. A dictionary stands in for
    /// the preferences, so the test leaves no preference domain behind on the machine.
    @Test func appliedToAStoredDomain() {
        var stored: [String: Any] = ["appearance": "dark", "agent.claude.enabled": true, "onboarding.completed": true]
        for key in SettingsReset.keysToRemove(from: stored, keeping: ["onboarding.completed"]) {
            stored.removeValue(forKey: key)
        }
        #expect(stored.keys.sorted() == ["onboarding.completed"])
    }
}
