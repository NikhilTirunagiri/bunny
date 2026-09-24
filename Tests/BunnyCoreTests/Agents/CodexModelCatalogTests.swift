import Foundation
import Testing
@testable import BunnyCore

@MainActor
struct CodexModelCatalogTests {
    private func fetch(cliPath: String, environment extra: [String: String] = [:], timeout: TimeInterval = 8) async -> (models: [CodexModel]?, onMain: Bool) {
        var environment = ProcessInfo.processInfo.environment
        environment.merge(extra) { _, new in new }
        return await withCheckedContinuation { continuation in
            CodexModelCatalog.fetch(cliPath: cliPath, environment: environment, timeout: timeout) { models in
                continuation.resume(returning: (models, Thread.isMainThread))
            }
        }
    }

    @Test func fetchesModelsFromFakeCodex() async {
        let result = await fetch(cliPath: FakeCLI.codex)
        let expected = [
            CodexModel(id: "gpt-fake", displayName: "GPT-Fake", efforts: ["low", "medium", "high"], defaultEffort: "medium", isDefault: true),
            CodexModel(id: "gpt-fake-mini", displayName: "GPT-Fake-Mini", efforts: ["low"], defaultEffort: "low", isDefault: false),
        ]
        #expect(result.models == expected)
        #expect(result.onMain)
    }

    @Test func errorResponseCompletesWithNil() async {
        let result = await fetch(cliPath: FakeCLI.codex, environment: ["FAKE_CODEX_MODEL_LIST": "error"])
        #expect(result.models == nil)
        #expect(result.onMain)
    }

    @Test func earlyExitCompletesWithNil() async {
        let result = await fetch(cliPath: FakeCLI.codex, environment: ["FAKE_CODEX_MODEL_LIST": "exit"])
        #expect(result.models == nil)
    }

    @Test func timeoutCompletesWithNil() async {
        let started = Date()
        let result = await fetch(cliPath: FakeCLI.codex, environment: ["FAKE_CODEX_MODEL_LIST": "hang"], timeout: 0.5)
        let elapsed = Date().timeIntervalSince(started)
        #expect(result.models == nil)
        #expect(result.onMain)
        #expect(elapsed < 5)
    }

    @Test func missingCLICompletesWithNil() async {
        let result = await fetch(cliPath: "/nonexistent/codex")
        #expect(result.models == nil)
        #expect(result.onMain)
    }

    @Test func fetchIsCallableOffMain() async {
        let environment = ProcessInfo.processInfo.environment
        let path = FakeCLI.codex
        let result: ([CodexModel]?, Bool) = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                CodexModelCatalog.fetch(cliPath: path, environment: environment) { models in
                    continuation.resume(returning: (models, Thread.isMainThread))
                }
            }
        }
        #expect(result.0?.count == 2)
        #expect(result.1)
    }
}
