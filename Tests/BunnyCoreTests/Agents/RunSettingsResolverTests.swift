import Foundation
import Testing
@testable import BunnyCore

struct RunSettingsResolverTests {
    private static let settingsModels: [AgentHarness: String] = [.claudeCode: "sonnet", .codex: ""]
    private static let settingsEfforts: [AgentHarness: String] = [.claudeCode: "", .codex: "medium"]

    private func resolve(requested: AgentHarness? = nil, harness: String?, model: String?, effort: String?,
                         defaultHarness: AgentHarness = .claudeCode) -> RunSettings {
        RunSettingsResolver.resolve(
            requestedHarness: requested,
            taskHarness: harness,
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

    @Test func taskHarnessWinsOverDefault() {
        let settings = resolve(harness: "claudeCode", model: nil, effort: nil, defaultHarness: .codex)
        #expect(settings.harness == .claudeCode)
        #expect(settings.model == "sonnet")
        #expect(settings.effort == nil)
    }

    @Test func overridesApplyForTheirHarness() {
        let settings = resolve(harness: "codex", model: "gpt-6-luna", effort: "high")
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
        let settings = resolve(requested: .claudeCode, harness: "claudeCode", model: "opus", effort: nil)
        #expect(settings == RunSettings(harness: .claudeCode, model: "opus", effort: nil, usesTaskOverrides: true))
    }

    @Test func blankValuesMeanTheCLIDefault() {
        let settings = resolve(harness: "codex", model: "  ", effort: "")
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
