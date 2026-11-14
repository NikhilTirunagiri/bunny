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

    /// How a model alias or effort level reads in menus ("opus" → "Opus", "xhigh" → "Extra high").
    /// Full model ids and anything with a digit, dash or dot are shown as they are.
    static func displayName(_ raw: String) -> String {
        if raw == "xhigh" { return "Extra high" }
        guard !raw.isEmpty, raw.allSatisfy({ $0.isLetter }) else { return raw }
        return raw.prefix(1).uppercased() + raw.dropFirst()
    }

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

    // MARK: - Real names for "Default"

    /// What a model id is called: Codex's display name when the model list has it, else the id.
    static func modelName(_ id: String, codexModels: [CodexModel]) -> String {
        codexModels.first { $0.id == id }?.displayName ?? id
    }

    /// The model a run uses when the note picks none: Settings' model, else the one the CLI reports
    /// as its default (Codex: from the model list; Claude Code: the model its last default run
    /// reported). nil = not known yet; the UI then says "Default".
    static func defaultModelName(for harness: AgentHarness, settingsModel: String, codexModels: [CodexModel],
                                 lastClaudeModel: String?) -> String? {
        if let model = AgentRunnerText.nonEmpty(settingsModel) { return modelName(model, codexModels: codexModels) }
        switch harness {
        case .claudeCode: return AgentRunnerText.nonEmpty(lastClaudeModel)
        case .codex: return codexModels.first(where: \.isDefault)?.displayName
        }
    }

    /// The effort a run uses when the note picks none: Settings' effort, else for Codex the default
    /// effort of `modelID` (blank = the default model). nil = not known; Claude Code reports none.
    static func defaultEffortName(for harness: AgentHarness, settingsEffort: String, modelID: String?,
                                  codexModels: [CodexModel]) -> String? {
        if let effort = AgentRunnerText.nonEmpty(settingsEffort) { return effort }
        guard harness == .codex else { return nil }
        let model = AgentRunnerText.nonEmpty(modelID).map { id in codexModels.first { $0.id == id } }
            ?? codexModels.first(where: \.isDefault)
        return model?.defaultEffort
    }
}
