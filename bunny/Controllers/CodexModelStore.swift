import Foundation
import Observation

/// The Codex model list (`model/list`), shared by Settings → Agents and the per-task agent menu
/// (spec §2, "cached in memory"). Fetched once at launch off the main thread and again whenever
/// Settings opens; a failed refresh keeps the last good list. Empty `models` with `isLoading` false
/// means the list is unavailable (codex missing, or the call failed) — Default/Custom still work.
@MainActor
@Observable
final class CodexModelStore {
    static let shared = CodexModelStore()
    private init() {}

    private(set) var models: [CodexModel] = []
    private(set) var isLoading = false

    /// Bumped by `reset()`, so a fetch started for an old CLI path can't overwrite the new result.
    @ObservationIgnored private var generation = 0

    /// Fetches unless a list is already loaded or a fetch is running (e.g. from a menu).
    func loadIfNeeded() {
        guard models.isEmpty else { return }
        refresh()
    }

    /// Re-queries the CLI (no-op while a fetch is running).
    func refresh() {
        guard !isLoading else { return }
        let cliPath = AgentSettings.cliPath(for: .codex)
        guard !cliPath.isEmpty, FileManager.default.isExecutableFile(atPath: cliPath) else { return }
        isLoading = true
        let current = generation
        // ShellEnvironment.environment() may run a login shell (≤3 s): always off-main.
        // `CodexModelCatalog.fetch` is `nonisolated` and hops to main itself to launch the CLI.
        DispatchQueue.global(qos: .utility).async {
            let environment = ShellEnvironment.environment()
            CodexModelCatalog.fetch(cliPath: cliPath, environment: environment) { fetched in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        CodexModelStore.shared.finish(fetched, generation: current)
                    }
                }
            }
        }
    }

    /// Forgets the list and fetches again (e.g. after the Codex path changed).
    func reset() {
        generation += 1
        models = []
        isLoading = false
        refresh()
    }

    private func finish(_ fetched: [CodexModel]?, generation fetchGeneration: Int) {
        guard fetchGeneration == generation else { return }
        isLoading = false
        if let fetched {
            models = fetched
        }
    }
}
