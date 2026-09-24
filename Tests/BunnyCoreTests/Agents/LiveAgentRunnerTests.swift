import Foundation
import Testing
@testable import BunnyCore

/// Smoke tests against the real CLIs. Opt in with `BUNNY_LIVE_AGENT_TESTS=1 swift test --filter Live`.
/// The Bunny-tools tests use cheap models: Claude `haiku`, Codex `BUNNY_LIVE_CODEX_MODEL` (default gpt-5.6-luna).
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BUNNY_LIVE_AGENT_TESTS"] == "1"))
struct LiveAgentRunnerTests {
    @Test func liveClaudeCode() async throws {
        try await runLive(harness: .claudeCode, cli: "claude") { ClaudeCodeRunner(options: $0) }
    }

    @Test func liveCodex() async throws {
        try await runLive(harness: .codex, cli: "codex") { CodexRunner(options: $0) }
    }

    /// Claude creates a task through a local MCP server via `--mcp-config` + `--allowedTools mcp__bunny`.
    @Test func liveClaudeCodeCreatesTaskWithBunnyTools() async throws {
        try await runLiveTools(harness: .claudeCode, cli: "claude", model: "haiku", effort: nil) { ClaudeCodeRunner(options: $0) }
    }

    /// Codex creates a task through a local MCP server under `approvalPolicy: never` + `workspace-write`.
    @Test func liveCodexCreatesTaskWithBunnyTools() async throws {
        let model = ProcessInfo.processInfo.environment["BUNNY_LIVE_CODEX_MODEL"] ?? "gpt-5.6-luna"
        try await runLiveTools(harness: .codex, cli: "codex", model: model, effort: "low") { CodexRunner(options: $0) }
    }

    private func liveEnvironment() -> [String: String] {
        var environment = ShellEnvironment.environment()
        // Tests may run inside a Claude Code session; don't let the child think it is nested.
        for key in environment.keys where key.hasPrefix("CLAUDECODE") || key.hasPrefix("CLAUDE_CODE_") {
            environment[key] = nil
        }
        return environment
    }

    private func runLiveTools(
        harness: AgentHarness,
        cli: String,
        model: String,
        effort: String?,
        make: (AgentRunOptions) -> AgentRunner
    ) async throws {
        let path = try #require(ShellEnvironment.locate(cli), "\(cli) not found on the login PATH")
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-live-tools-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let callsLog = scratch.appendingPathComponent("calls.jsonl")

        let token = UUID().uuidString
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        server.arguments = ["python3", FakeCLI.directory.appendingPathComponent("fake_mcp_http.py").path, token, callsLog.path]
        let serverOutput = Pipe()
        server.standardOutput = serverOutput
        try server.run()
        defer { server.terminate() }
        let firstLine = String(decoding: serverOutput.fileHandleForReading.availableData, as: UTF8.self)
        let port = try #require(firstLine.split(separator: " ").last.flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) })

        let taskID = UUID()
        var options = AgentRunOptions(cliPath: path, autonomy: .autonomous, environment: liveEnvironment())
        options.model = model
        options.effort = effort
        options.tools = BunnyToolsEndpoint(url: "http://127.0.0.1:\(port)/mcp", token: token, taskID: taskID)
        let runner = make(options)
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        let workspace = scratch.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        var brief = makeBrief(title: "Live Bunny tools test")
        brief.workingDirectory = workspace.path

        runner.start(
            brief: brief,
            harness: harness,
            resumeSessionID: nil,
            initialMessage: "Use the bunny create_task tool to create a task titled LiveBunnyTask. Then reply with the word OK and nothing else."
        )

        let settled = await recorder.wait(timeout: 180) { events in
            !events.turnsFinished.isEmpty || !events.questions.isEmpty || !events.failures.isEmpty || !events.exitCodes.isEmpty
        }
        #expect(settled)
        let events = recorder.events
        #expect(events.failures.isEmpty, "failures: \(events.failures)")
        #expect(events.questions.isEmpty, "unexpected question: \(events.questions)")
        let finished = try #require(events.turnsFinished.first, "activity: \(events.activities)")
        #expect(finished.success, "text: \(finished.text)")

        let log = (try? String(contentsOf: callsLog, encoding: .utf8)) ?? ""
        let calls = log.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
        let call = try #require(calls.first, "no create_task call reached the server; reply: \(finished.text)")
        #expect((call["arguments"] as? [String: Any])?["title"] as? String == "LiveBunnyTask")
        #expect(call["task"] as? String == taskID.uuidString)
    }

    private func runLive(harness: AgentHarness, cli: String, make: (AgentRunOptions) -> AgentRunner) async throws {
        let path = try #require(ShellEnvironment.locate(cli), "\(cli) not found on the login PATH")
        let runner = make(AgentRunOptions(cliPath: path, autonomy: .autonomous, environment: liveEnvironment()))
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
