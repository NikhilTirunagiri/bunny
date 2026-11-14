import Foundation
import Testing
@testable import BunnyCore

struct RunSettingsResolverTests {
    private static let settingsModels: [AgentHarness: String] = [.claudeCode: "sonnet", .codex: ""]
    private static let settingsEfforts: [AgentHarness: String] = [.claudeCode: "", .codex: "medium"]

    private func resolve(requested: AgentHarness? = nil, harness: String?, model: String?, effort: String?,
                         chosen: Bool = false, hasSession: Bool = false, sessionHarness: String? = nil,
                         freshRun: Bool = false, defaultHarness: AgentHarness = .claudeCode) -> RunSettings {
        RunSettingsResolver.resolve(
            requestedHarness: requested,
            taskHarness: harness,
            harnessIsChosen: chosen,
            hasSession: hasSession,
            sessionHarness: sessionHarness,
            freshRun: freshRun,
            taskModel: model,
            taskEffort: effort,
            defaultHarness: defaultHarness,
            settingsModel: { Self.settingsModels[$0] ?? "" },
            settingsEffort: { Self.settingsEfforts[$0] ?? "" }
        )
    }

    @Test func noTaskChoiceUsesDefaultHarnessAndSettings() {
        let settings = resolve(harness: nil, model: nil, effort: nil, defaultHarness: .codex)
        #expect(settings == RunSettings(harness: .codex, model: nil, effort: "medium", usesTaskOverrides: false))
    }

    @Test func explicitChoiceWinsOverDefault() {
        let settings = resolve(harness: "claudeCode", model: nil, effort: nil, chosen: true, defaultHarness: .codex)
        #expect(settings.harness == .claudeCode)
        #expect(settings.model == "sonnet")
        #expect(settings.effort == nil)
    }

    @Test func existingSessionKeepsItsHarness() {
        let settings = resolve(harness: "codex", model: nil, effort: nil, hasSession: true, defaultHarness: .claudeCode)
        #expect(settings.harness == .codex)
    }

    // MARK: - Fresh run ("Hand off again") and the session's own agent

    @Test func freshRunIgnoresTheOldSessionsHarness() {
        // Handed off to Codex once (recorded, not chosen); the default is Claude Code now.
        let again = resolve(harness: "codex", model: nil, effort: nil, hasSession: true, sessionHarness: "codex",
                            freshRun: true, defaultHarness: .claudeCode)
        #expect(again.harness == .claudeCode)
        #expect(again.model == "sonnet")
    }

    @Test func freshRunHonoursAChoiceMadeInTheCard() {
        // The session is Claude Code's; the card picked Codex with a model for the next hand-off.
        let again = resolve(harness: "codex", model: "gpt-6-luna", effort: nil, chosen: true, hasSession: true,
                            sessionHarness: "claudeCode", freshRun: true)
        #expect(again == RunSettings(harness: .codex, model: "gpt-6-luna", effort: "medium", usesTaskOverrides: true))
    }

    @Test func theSessionKeepsItsOwnAgentAfterTheCardPickedAnother() {
        // Opening or messaging the old session: its agent, not the next hand-off's, and not its model.
        let session = resolve(harness: "codex", model: "gpt-6-luna", effort: nil, chosen: true, hasSession: true,
                              sessionHarness: "claudeCode")
        #expect(session == RunSettings(harness: .claudeCode, model: "sonnet", effort: nil, usesTaskOverrides: false))
    }

    @Test func aSessionWithoutARecordedAgentUsesTheNotesAgent() {
        // Notes from before the session's agent was stored apart.
        #expect(resolve(harness: "codex", model: nil, effort: nil, hasSession: true, sessionHarness: nil).harness == .codex)
    }

    @Test func freshRunWithoutASessionIsTheSameAsBefore() {
        #expect(resolve(harness: "codex", model: nil, effort: nil, freshRun: true) == resolve(harness: "codex", model: nil, effort: nil))
        #expect(resolve(harness: "codex", model: nil, effort: nil, chosen: true, freshRun: true).harness == .codex)
    }

    @Test func failedRunWithoutSessionOrChoiceUsesDefault() {
        // The last run recorded codex, but nothing was chosen and there is no session to resume.
        let settings = resolve(harness: "codex", model: nil, effort: nil, defaultHarness: .claudeCode)
        #expect(settings.harness == .claudeCode)
        #expect(settings.model == "sonnet")
    }

    @Test func overridesApplyForTheirHarness() {
        let settings = resolve(harness: "codex", model: "gpt-6-luna", effort: "high", chosen: true)
        #expect(settings == RunSettings(harness: .codex, model: "gpt-6-luna", effort: "high", usesTaskOverrides: true))
    }

    @Test func overridesIgnoredWithoutAHarness() {
        // Legacy data: a model chosen without recording the harness it was chosen for.
        let settings = resolve(harness: nil, model: "opus", effort: "max")
        #expect(settings == RunSettings(harness: .claudeCode, model: "sonnet", effort: nil, usesTaskOverrides: false))
    }

    @Test func overridesIgnoredForAnotherRequestedHarness() {
        let settings = resolve(requested: .codex, harness: "claudeCode", model: "opus", effort: "max")
        #expect(settings == RunSettings(harness: .codex, model: nil, effort: "medium", usesTaskOverrides: false))
    }

    @Test func requestedHarnessMatchingTaskKeepsOverrides() {
        let settings = resolve(requested: .claudeCode, harness: "claudeCode", model: "opus", effort: nil, chosen: true)
        #expect(settings == RunSettings(harness: .claudeCode, model: "opus", effort: nil, usesTaskOverrides: true))
    }

    @Test func blankValuesMeanTheCLIDefault() {
        let settings = resolve(harness: "codex", model: "  ", effort: "", chosen: true)
        // Blank overrides fall back to Settings; blank Settings resolve to nil.
        #expect(settings == RunSettings(harness: .codex, model: nil, effort: "medium", usesTaskOverrides: false))
    }

    @Test func unknownTaskHarnessFallsBackToDefault() {
        let settings = resolve(harness: "gemini", model: "x", effort: "y", defaultHarness: .codex)
        #expect(settings == RunSettings(harness: .codex, model: nil, effort: "medium", usesTaskOverrides: false))
    }

    @Test func captionShowsDefaults() {
        #expect(RunSettingsResolver.caption(RunSettings(harness: .codex, model: nil, effort: "high", usesTaskOverrides: false))
                == "Codex · Default · high")
    }

    // MARK: - AgentModelOptions

    @Test func effortOptions() {
        let models = [CodexModel(id: "m1", displayName: "M1", efforts: ["low", "xhigh"], defaultEffort: nil, isDefault: true)]
        #expect(AgentModelOptions.efforts(for: .claudeCode, modelID: "m1", codexModels: models) == AgentModelOptions.claudeEfforts)
        #expect(AgentModelOptions.efforts(for: .codex, modelID: "m1", codexModels: models) == ["low", "xhigh"])
        #expect(AgentModelOptions.efforts(for: .codex, modelID: nil, codexModels: models) == AgentModelOptions.codexFallbackEfforts)
        #expect(AgentModelOptions.efforts(for: .codex, modelID: "custom", codexModels: models) == AgentModelOptions.codexFallbackEfforts)
    }
}

struct RunSettingsEnablementTests {
    private func resolve(taskHarness: String?, chosen: Bool, hasSession: Bool = false,
                         isEnabled: @escaping (AgentHarness) -> Bool) -> AgentHarness {
        RunSettingsResolver.resolve(taskHarness: taskHarness, harnessIsChosen: chosen, hasSession: hasSession,
                                    taskModel: nil, taskEffort: nil, defaultHarness: .claudeCode,
                                    settingsModel: { _ in "" }, settingsEffort: { _ in "" }, isEnabled: isEnabled).harness
    }

    @Test func aChosenAgentThatIsSwitchedOffFallsBackToTheDefault() {
        #expect(resolve(taskHarness: "codex", chosen: true) { $0 == .claudeCode } == .claudeCode)
        #expect(resolve(taskHarness: "codex", chosen: true) { _ in true } == .codex)
    }

    @Test func anExistingSessionKeepsItsAgentEvenWhenSwitchedOff() {
        #expect(resolve(taskHarness: "codex", chosen: false, hasSession: true) { $0 == .claudeCode } == .codex)
    }
}

struct AgentModelNameTests {
    private let models = [
        CodexModel(id: "gpt-a", displayName: "GPT-A", efforts: ["low", "high"], defaultEffort: "low", isDefault: false),
        CodexModel(id: "gpt-b", displayName: "GPT-B", efforts: ["medium", "high"], defaultEffort: "medium", isDefault: true),
    ]

    @Test func codexDefaultModelIsTheOneTheCLIReports() {
        #expect(AgentModelOptions.defaultModelName(for: .codex, settingsModel: "", codexModels: models, lastClaudeModel: nil) == "GPT-B")
        #expect(AgentModelOptions.defaultModelName(for: .codex, settingsModel: "", codexModels: [], lastClaudeModel: "x") == nil)
    }

    @Test func settingsModelIsTheDefaultWhenSet() {
        #expect(AgentModelOptions.defaultModelName(for: .codex, settingsModel: "gpt-a", codexModels: models, lastClaudeModel: nil) == "GPT-A")
        #expect(AgentModelOptions.defaultModelName(for: .claudeCode, settingsModel: "opus", codexModels: [], lastClaudeModel: "claude-x") == "opus")
    }

    @Test func claudeDefaultModelIsTheLastReportedOne() {
        #expect(AgentModelOptions.defaultModelName(for: .claudeCode, settingsModel: "", codexModels: models, lastClaudeModel: "claude-fable-5") == "claude-fable-5")
        #expect(AgentModelOptions.defaultModelName(for: .claudeCode, settingsModel: "", codexModels: models, lastClaudeModel: nil) == nil)
        #expect(AgentModelOptions.defaultModelName(for: .claudeCode, settingsModel: "", codexModels: models, lastClaudeModel: " ") == nil)
    }

    @Test func modelNamesUseTheCodexDisplayName() {
        #expect(AgentModelOptions.modelName("gpt-a", codexModels: models) == "GPT-A")
        #expect(AgentModelOptions.modelName("custom-1", codexModels: models) == "custom-1")
    }

    @Test func defaultEffortNames() {
        // Codex: the chosen model's default, else the default model's.
        #expect(AgentModelOptions.defaultEffortName(for: .codex, settingsEffort: "", modelID: "gpt-a", codexModels: models) == "low")
        #expect(AgentModelOptions.defaultEffortName(for: .codex, settingsEffort: "", modelID: nil, codexModels: models) == "medium")
        #expect(AgentModelOptions.defaultEffortName(for: .codex, settingsEffort: "", modelID: "custom", codexModels: models) == nil)
        #expect(AgentModelOptions.defaultEffortName(for: .codex, settingsEffort: "high", modelID: nil, codexModels: models) == "high")
        // Claude Code reports no effort.
        #expect(AgentModelOptions.defaultEffortName(for: .claudeCode, settingsEffort: "", modelID: nil, codexModels: models) == nil)
        #expect(AgentModelOptions.defaultEffortName(for: .claudeCode, settingsEffort: "max", modelID: nil, codexModels: models) == "max")
    }
}
