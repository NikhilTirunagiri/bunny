import Foundation

/// The harness, model and effort a run actually uses (nil model/effort = the CLI's default).
struct RunSettings: Equatable {
    var harness: AgentHarness
    var model: String?
    var effort: String?
    /// Whether the task's own model/effort overrides were used (they were chosen for `harness`).
    var usesTaskOverrides: Bool
}

/// Single source of truth for what a task's next run uses. Pure: every input is passed in.
///
/// - Harness: `requestedHarness` (an explicit choice for this run), else the task's chosen harness,
///   else Settings' default.
/// - Model/effort: the task's override, but only when it was chosen for the resolved harness
///   (`taskHarness == harness`); otherwise Settings' value for that harness. Blank values mean
///   "the CLI's default" and resolve to nil.
enum RunSettingsResolver {
    static func resolve(
        requestedHarness: AgentHarness? = nil,
        taskHarness: String?,
        taskModel: String?,
        taskEffort: String?,
        defaultHarness: AgentHarness,
        settingsModel: (AgentHarness) -> String,
        settingsEffort: (AgentHarness) -> String
    ) -> RunSettings {
        let chosenHarness = taskHarness.flatMap(AgentHarness.init(rawValue:))
        let harness = requestedHarness ?? chosenHarness ?? defaultHarness
        let overridesApply = chosenHarness == harness
        let model = (overridesApply ? AgentRunnerText.nonEmpty(taskModel) : nil)
            ?? AgentRunnerText.nonEmpty(settingsModel(harness))
        let effort = (overridesApply ? AgentRunnerText.nonEmpty(taskEffort) : nil)
            ?? AgentRunnerText.nonEmpty(settingsEffort(harness))
        let usesTaskOverrides = overridesApply
            && (AgentRunnerText.nonEmpty(taskModel) != nil || AgentRunnerText.nonEmpty(taskEffort) != nil)
        return RunSettings(harness: harness, model: model, effort: effort, usesTaskOverrides: usesTaskOverrides)
    }

    /// "<Harness> · <model> · <effort>", with "Default" for the CLI's default.
    static func caption(_ settings: RunSettings) -> String {
        "\(settings.harness.displayName) · \(settings.model ?? "Default") · \(settings.effort ?? "Default")"
    }
}
