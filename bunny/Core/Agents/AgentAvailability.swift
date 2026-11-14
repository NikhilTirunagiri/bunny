import Foundation

/// Which agents the user switched on, and what that means for the default agent. Pure.
enum AgentAvailability {
    /// The switched-on agents, in menu order. Empty: the app shows no agent controls at all.
    static func available(isEnabled: (AgentHarness) -> Bool) -> [AgentHarness] {
        AgentHarness.allCases.filter(isEnabled)
    }

    /// The agent a hand-off uses by default: Settings' choice while it is switched on, else the other
    /// switched-on agent, else none.
    static func effectiveDefault(stored: AgentHarness, available: [AgentHarness]) -> AgentHarness? {
        available.contains(stored) ? stored : available.first
    }

    /// The switches' first values, written once. A fresh install starts with both off; an install that
    /// already used agents (it has agent preferences, or notes with agent state) keeps the agents
    /// whose CLI it had found.
    static func migratedEnablement(hasAgentPreferences: Bool, hasAgentNotes: Bool,
                                   wasDetected: (AgentHarness) -> Bool) -> [AgentHarness] {
        guard hasAgentPreferences || hasAgentNotes else { return [] }
        return AgentHarness.allCases.filter(wasDetected)
    }
}

/// Whether Bunny tools were installed for every session of a CLI (Settings → Agents → Bunny tools),
/// read from the CLIs' own config files: `~/.claude.json` and `~/.codex/config.toml`. Pure.
enum BunnyToolsGlobalInstall {
    static func isPresent(claudeConfig: Data?, codexConfig: String?) -> Bool {
        if let claudeConfig,
           let root = try? JSONSerialization.jsonObject(with: claudeConfig) as? [String: Any],
           let servers = root["mcpServers"] as? [String: Any],
           servers[BunnyToolsEndpoint.serverName] != nil {
            return true
        }
        if let codexConfig {
            return codexConfig.split(whereSeparator: \.isNewline)
                .contains { CodexConfigPatcher.tableName(String($0)) == CodexConfigPatcher.serverTable }
        }
        return false
    }
}
