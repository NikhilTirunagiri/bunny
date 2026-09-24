import Foundation
import Testing
@testable import BunnyCore

/// Smoke tests against the real CLIs. Opt in with `BUNNY_LIVE_AGENT_TESTS=1 swift test --filter Live`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BUNNY_LIVE_AGENT_TESTS"] == "1"))
struct LiveAgentRunnerTests {
    @Test func liveClaudeCode() async throws {
        try await runLive(harness: .claudeCode, cli: "claude") { ClaudeCodeRunner(options: $0) }
    }

    @Test func liveCodex() async throws {
        try await runLive(harness: .codex, cli: "codex") { CodexRunner(options: $0) }
    }

    private func runLive(harness: AgentHarness, cli: String, make: (AgentRunOptions) -> AgentRunner) async throws {
        let path = try #require(ShellEnvironment.locate(cli), "\(cli) not found on the login PATH")
        var environment = ShellEnvironment.environment()
        // Tests may run inside a Claude Code session; don't let the child think it is nested.
        for key in environment.keys where key.hasPrefix("CLAUDECODE") || key.hasPrefix("CLAUDE_CODE_") {
            environment[key] = nil
        }
        let runner = make(AgentRunOptions(cliPath: path, autonomy: .autonomous, environment: environment))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        var brief = makeBrief(title: "Live smoke test")
        brief.workingDirectory = workspace.path

        runner.start(brief: brief, harness: harness, resumeSessionID: nil, initialMessage: "Reply with the word OK and nothing else.")

        let settled = await recorder.wait(timeout: 120) { events in
            !events.turnsFinished.isEmpty || !events.questions.isEmpty || !events.failures.isEmpty || !events.exitCodes.isEmpty
        }
        #expect(settled)
        let events = recorder.events
        #expect(events.failures.isEmpty, "failures: \(events.failures)")
        #expect(!events.sessionIDs.isEmpty)
        // The model can (wrongly) end with a <bunny-question>; the runner then reports a question instead.
        #expect(events.questions.isEmpty, "unexpected question: \(events.questions)")
        let finished = try #require(events.turnsFinished.first, "activity: \(events.activities)")
        #expect(finished.success, "text: \(finished.text)")
        #expect(finished.text.uppercased().contains("OK"))
    }
}
