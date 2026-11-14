import Foundation
import Observation
import SwiftData

/// Which agents are switched on, and whether Bunny tools are (v3 spec §7 "Enable"). Observable, so
/// every agent control appears and disappears live. Off means nothing of that agent runs: no CLI
/// lookup, no model list, and with both off no login shell and no Bunny tools listener either.
@MainActor
@Observable
final class AgentEnablement {
    static let shared = AgentEnablement()

    private var enabled: Set<AgentHarness>
    /// Settings' default agent, mirrored here so views that show it update when it changes.
    private var storedDefault: AgentHarness
    /// Bunny tools (the local MCP server) are switched on. The listener runs while this and an agent are on.
    private(set) var tools: Bool

    private init() {
        enabled = Set(AgentHarness.allCases.filter(AgentSettings.isEnabled))
        storedDefault = AgentSettings.defaultHarness
        tools = AgentSettings.toolsEnabled
    }

    func isEnabled(_ harness: AgentHarness) -> Bool { enabled.contains(harness) }

    /// The switched-on agents, in menu order.
    var available: [AgentHarness] { AgentAvailability.available(isEnabled: isEnabled) }
    var anyEnabled: Bool { !enabled.isEmpty }

    /// The default agent: Settings' choice, or the other agent while that one is off; nil with both off.
    var defaultHarness: AgentHarness? {
        AgentAvailability.effectiveDefault(stored: storedDefault, available: available)
    }

    func setDefault(_ harness: AgentHarness) {
        storedDefault = harness
        AgentSettings.defaultHarness = harness
    }

    /// The switch in Settings. Switching the default agent off moves the default to the other one.
    /// Switching one on looks for its CLI right then (unless its path already works), and for Codex
    /// fetches the model list. An agent whose CLI is not found can still be switched on: its row says
    /// "Not found" and a hand-off fails with the missing-CLI message until it is installed or its
    /// path is set. `detected` runs on main with the path found (nil: none, or not searched).
    func setEnabled(_ on: Bool, for harness: AgentHarness, detected: (@MainActor @Sendable (String?) -> Void)? = nil) {
        guard isEnabled(harness) != on else { return }
        if on { enabled.insert(harness) } else { enabled.remove(harness) }
        AgentSettings.setEnabled(on, for: harness)
        if let defaultHarness { setDefault(defaultHarness) }
        syncToolsServer()
        guard on else { return }
        let path = AgentSettings.cliPath(for: harness)
        if FileManager.default.isExecutableFile(atPath: path) {
            if harness == .codex { CodexModelStore.shared.loadIfNeeded() }
            detected?(path)
            return
        }
        AgentSettings.detect(harness) { found in
            if harness == .codex { CodexModelStore.shared.loadIfNeeded() }
            detected?(found)
        }
    }

    func setTools(_ on: Bool) {
        guard tools != on else { return }
        tools = on
        AgentSettings.toolsEnabled = on
        syncToolsServer()
    }

    /// Starts or stops the listener to match the switches.
    func syncToolsServer() {
        if tools && anyEnabled {
            BunnyToolsServer.shared.start()
        } else {
            BunnyToolsServer.shared.stop()
        }
    }

    /// Once, at the first launch that has the switches: a fresh install starts with everything off;
    /// an install that used agents keeps the agents whose CLI it had found, and keeps Bunny tools on
    /// only if they were installed for every session of a CLI. Reads the store, the preferences and
    /// two config files; starts nothing.
    func migrateIfNeeded(context: ModelContext) {
        guard !AgentSettings.enablementIsStored else { return }
        let idle = AgentRunState.idle.rawValue
        let agentNotes = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.agentState != idle || $0.agentSessionID != nil })
        let hasAgentPreferences = AgentSettings.hasAgentPreferences
        let hasAgentNotes = ((try? context.fetchCount(agentNotes)) ?? 0) > 0
        let migrated = AgentAvailability.migratedEnablement(
            hasAgentPreferences: hasAgentPreferences,
            hasAgentNotes: hasAgentNotes,
            wasDetected: { !AgentSettings.cliPath(for: $0).isEmpty }
        )
        for harness in AgentHarness.allCases {
            AgentSettings.setEnabled(migrated.contains(harness), for: harness)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? home.appendingPathComponent(".codex")
        AgentSettings.toolsEnabled = (hasAgentPreferences || hasAgentNotes) && BunnyToolsGlobalInstall.isPresent(
            claudeConfig: try? Data(contentsOf: home.appendingPathComponent(".claude.json")),
            codexConfig: try? String(contentsOf: codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        )
        enabled = Set(migrated)
        tools = AgentSettings.toolsEnabled
    }

    #if DEBUG
    /// Snapshots only: sets the switches in memory; nothing is saved or started.
    func snapshotSet(_ harnesses: [AgentHarness], tools: Bool = false) {
        enabled = Set(harnesses)
        self.tools = tools
    }
    #endif
}
