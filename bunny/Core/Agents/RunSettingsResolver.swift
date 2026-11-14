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
/// - Harness: `requestedHarness` (an explicit choice for this run), else the harness of the task's
///   session (`hasSession`: `sessionHarness`, or `taskHarness` for a note from before that was
///   recorded), else the one chosen in the options card (`harnessIsChosen`) while it is still switched
///   on (`isEnabled`), else Settings' default. A harness merely recorded by a past run does not
///   outrank Settings.
/// - `freshRun` (Hand off / Hand off again, and the card and caption that announce it): a new
///   session, so the old session and its harness do not count: the choice, else the default.
/// - Model/effort: the task's override, but only when it was chosen for the resolved harness
///   (`taskHarness == harness`); otherwise Settings' value for that harness. Blank values mean
///   "the CLI's default" and resolve to nil.
enum RunSettingsResolver {
    static func resolve(
        requestedHarness: AgentHarness? = nil,
        taskHarness: String?,
        harnessIsChosen: Bool,
        hasSession: Bool,
        sessionHarness: String? = nil,
        freshRun: Bool = false,
        taskModel: String?,
        taskEffort: String?,
        defaultHarness: AgentHarness,
        settingsModel: (AgentHarness) -> String,
        settingsEffort: (AgentHarness) -> String,
        isEnabled: (AgentHarness) -> Bool = { _ in true }
    ) -> RunSettings {
        let chosenHarness = taskHarness.flatMap(AgentHarness.init(rawValue:))
        let binding: AgentHarness?
        if hasSession && !freshRun {
            binding = sessionHarness.flatMap(AgentHarness.init(rawValue:)) ?? chosenHarness
        } else {
            binding = harnessIsChosen ? chosenHarness.flatMap { isEnabled($0) ? $0 : nil } : nil
        }
        let harness = requestedHarness ?? binding ?? defaultHarness
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
