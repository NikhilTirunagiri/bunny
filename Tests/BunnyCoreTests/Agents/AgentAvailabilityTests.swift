import Testing
import Foundation
@testable import BunnyCore

struct AgentAvailabilityTests {
    @Test func availableListsEnabledAgentsInOrder() {
        #expect(AgentAvailability.available { _ in true } == [.claudeCode, .codex])
        #expect(AgentAvailability.available { $0 == .codex } == [.codex])
        #expect(AgentAvailability.available { _ in false }.isEmpty)
    }

    @Test func effectiveDefaultKeepsAnEnabledStoredDefault() {
        #expect(AgentAvailability.effectiveDefault(stored: .codex, available: [.claudeCode, .codex]) == .codex)
        #expect(AgentAvailability.effectiveDefault(stored: .claudeCode, available: [.claudeCode]) == .claudeCode)
    }

    @Test func effectiveDefaultMovesToTheOtherEnabledAgent() {
        #expect(AgentAvailability.effectiveDefault(stored: .claudeCode, available: [.codex]) == .codex)
        #expect(AgentAvailability.effectiveDefault(stored: .codex, available: [.claudeCode]) == .claudeCode)
    }

    @Test func effectiveDefaultIsNilWithBothOff() {
        #expect(AgentAvailability.effectiveDefault(stored: .claudeCode, available: []) == nil)
    }

    @Test func freshInstallStartsWithBothOff() {
        let enabled = AgentAvailability.migratedEnablement(hasAgentPreferences: false, hasAgentNotes: false) { _ in true }
        #expect(enabled.isEmpty)
    }

    @Test func existingInstallKeepsTheAgentsThatWereDetected() {
        #expect(AgentAvailability.migratedEnablement(hasAgentPreferences: true, hasAgentNotes: false) { $0 == .claudeCode } == [.claudeCode])
        #expect(AgentAvailability.migratedEnablement(hasAgentPreferences: false, hasAgentNotes: true) { _ in true } == [.claudeCode, .codex])
        #expect(AgentAvailability.migratedEnablement(hasAgentPreferences: true, hasAgentNotes: true) { _ in false }.isEmpty)
    }

    @Test func globalInstallIsFoundInClaudeConfig() {
        let installed = Data(#"{"numStartups":3,"mcpServers":{"bunny":{"type":"http","url":"http://127.0.0.1:47823/mcp"}}}"#.utf8)
        let other = Data(#"{"mcpServers":{"linear":{"type":"http"}},"projects":{"/x":{"mcpServers":{"bunny":{}}}}}"#.utf8)
        #expect(BunnyToolsGlobalInstall.isPresent(claudeConfig: installed, codexConfig: nil))
        #expect(!BunnyToolsGlobalInstall.isPresent(claudeConfig: other, codexConfig: nil))
        #expect(!BunnyToolsGlobalInstall.isPresent(claudeConfig: Data("not json".utf8), codexConfig: nil))
        #expect(!BunnyToolsGlobalInstall.isPresent(claudeConfig: nil, codexConfig: nil))
    }

    @Test func globalInstallIsFoundInCodexConfig() {
        let installed = "model = \"gpt\"\n\n[mcp_servers.bunny]\nurl = \"http://127.0.0.1:47823/mcp\"\n"
        let other = "[mcp_servers.linear]\nurl = \"x\"\n# [mcp_servers.bunny]\n"
        #expect(BunnyToolsGlobalInstall.isPresent(claudeConfig: nil, codexConfig: installed))
        #expect(!BunnyToolsGlobalInstall.isPresent(claudeConfig: nil, codexConfig: other))
    }
}
