import Foundation

/// The model and effort choices Bunny offers (spec §2), shared by Settings → Agents and the
/// per-task agent menu so both always list the same values.
enum AgentModelOptions {
    /// Claude Code `--model` aliases, in menu order. Settings also offers Default and Custom….
    static let claudeModelAliases = ["fable", "opus", "sonnet", "haiku"]
    /// Claude Code `--effort` levels, in menu order.
    static let claudeEfforts = ["low", "medium", "high", "xhigh", "max"]
    /// Codex efforts offered when the model's supported efforts aren't known (Default, Custom, or
    /// no model list).
    static let codexFallbackEfforts = ["low", "medium", "high"]

    /// The efforts to offer for `harness` with `modelID` selected (blank = the CLI's default model).
    static func efforts(for harness: AgentHarness, modelID: String?, codexModels: [CodexModel]) -> [String] {
        switch harness {
        case .claudeCode:
            return claudeEfforts
        case .codex:
            guard let modelID = AgentRunnerText.nonEmpty(modelID),
                  let model = codexModels.first(where: { $0.id == modelID }),
                  !model.efforts.isEmpty else { return codexFallbackEfforts }
            return model.efforts
        }
    }
}
