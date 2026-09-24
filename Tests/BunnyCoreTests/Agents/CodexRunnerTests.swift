import Foundation
import Testing
@testable import BunnyCore

@MainActor
struct CodexRunnerTests {
    @Test func codexHappyPath() async throws {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "Tidy the desk"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.waitForTurnFinished())
        let events = recorder.events
        #expect(events.sessionIDs == ["th-1"])
        #expect(runner.sessionID == "th-1")
        let finished = try #require(events.turnsFinished.first)
        #expect(finished.success)
        #expect(finished.text.hasPrefix("done: # Task: Tidy the desk"))
        #expect(events.activities.first == "done: # Task: Tidy the desk")
        #expect(events.failures.isEmpty)
        let sessionIndex = events.firstIndex { if case .sessionStarted = $0 { return true } else { return false } }
        let finishedIndex = events.firstIndex { if case .turnFinished = $0 { return true } else { return false } }
        let sessionFirst = (sessionIndex ?? Int.max) < (finishedIndex ?? Int.min)
        #expect(sessionFirst)
    }

    @Test func codexMarkerQuestionThenAnswer() async throws {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "QUESTION time"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.wait { !$0.questions.isEmpty })
        let question = try #require(recorder.events.questions.first)
        #expect(question.kind == .choices)
        #expect(question.requestID == nil)
        #expect(question.items.first?.question == "Which DB?")
        #expect(question.items.first?.options.map(\.label) == ["pg", "sqlite"])
        #expect(recorder.events.turnsFinished.isEmpty)

        runner.answer(question, with: AgentAnswer(selections: ["answer": ["sqlite"]], approved: nil))

        #expect(await recorder.waitForTurnFinished())
        let finished = try #require(recorder.events.turnsFinished.first)
        #expect(finished.success)
        #expect(finished.text.contains("sqlite"))
    }

    @Test func codexApprovalRequestRoundTrip() async throws {
        for approved in [true, false] {
            let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex, autonomy: .askFirst))
            let recorder = EventRecorder(runner)
            defer { runner.terminate() }

            runner.start(brief: makeBrief(title: "APPROVE it"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

            #expect(await recorder.wait { !$0.questions.isEmpty })
            let question = try #require(recorder.events.questions.first)
            #expect(question.kind == .approval)
            #expect(question.requestID == "99")
            #expect(question.method == "item/commandExecution/requestApproval")
            #expect(question.approvalDetail == "rm -rf build")
            #expect(recorder.events.activities.contains("Running rm -rf build"))

            runner.answer(question, with: AgentAnswer(selections: [:], approved: approved))

            #expect(await recorder.waitForTurnFinished())
            let expected = approved ? "approval: accept" : "approval: decline"
            #expect(recorder.events.turnsFinished.first?.text == expected)
        }
    }

    @Test func codexThreadStartUsesAutonomyPolicyAndWritableRoots() async throws {
        let cases: [(AgentAutonomy, String)] = [(.autonomous, "never"), (.askFirst, "on-request")]
        for (autonomy, policy) in cases {
            let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex, autonomy: autonomy))
            let recorder = EventRecorder(runner)
            defer { runner.terminate() }

            runner.start(brief: makeBrief(title: "POLICY check", extraDirectories: ["/tmp/extra"]), harness: .codex, resumeSessionID: nil, initialMessage: nil)

            #expect(await recorder.waitForTurnFinished())
            let expected = "policy: \(policy) sandbox: workspace-write roots: [\"/tmp/extra\"]"
            #expect(recorder.events.turnsFinished.first?.text == expected)
        }
    }

    private static let tools = BunnyToolsEndpoint(
        url: "http://127.0.0.1:47823/mcp",
        token: "secret-token",
        taskID: UUID(uuidString: "11111111-2222-3333-4444-555555555555")
    )

    /// Runs one CONFIG turn and returns the fake's echo of the thread/start (or resume) and turn/start params.
    private func configEcho(_ options: AgentRunOptions, resume: String? = nil, extraDirectories: [String] = []) async throws -> [String: Any] {
        let runner = CodexRunner(options: options)
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        let brief = makeBrief(title: "CONFIG check", extraDirectories: extraDirectories)
        runner.start(brief: brief, harness: .codex, resumeSessionID: resume, initialMessage: resume == nil ? nil : "CONFIG again")

        #expect(await recorder.waitForTurnFinished())
        let text = try #require(recorder.events.turnsFinished.first?.text)
        #expect(text.hasPrefix("config: "))
        let json = String(text.dropFirst("config: ".count))
        return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    @Test func codexDefaultsSendNoModelEffortOrTools() async throws {
        let echo = try await configEcho(FakeCLI.options(cliPath: FakeCLI.codex))
        let thread = try #require(echo["thread"] as? [String: Any])
        let turn = try #require(echo["turn"] as? [String: Any])
        #expect(thread["model"] == nil)
        #expect(thread["config"] == nil)
        #expect(thread["approvalPolicy"] as? String == "never")
        #expect(thread["sandbox"] as? String == "workspace-write")
        #expect(turn["effort"] == nil)
        #expect(echo["instructionsMentionBunnyTools"] as? Bool == false)
    }

    @Test func codexSendsModelEffortAndBunnyTools() async throws {
        var options = FakeCLI.options(cliPath: FakeCLI.codex)
        options.model = "gpt-6-luna"
        options.effort = "high"
        options.tools = Self.tools
        let echo = try await configEcho(options, extraDirectories: ["/tmp/extra"])
        let thread = try #require(echo["thread"] as? [String: Any])
        let turn = try #require(echo["turn"] as? [String: Any])
        let config = try #require(thread["config"] as? NSDictionary)
        let expectedConfig: NSDictionary = [
            "sandbox_workspace_write": ["writable_roots": ["/tmp/extra"]],
            "mcp_servers": [
                "bunny": [
                    "url": "http://127.0.0.1:47823/mcp",
                    "http_headers": [
                        "Authorization": "Bearer secret-token",
                        "X-Bunny-Task": "11111111-2222-3333-4444-555555555555",
                    ],
                    "default_tools_approval_mode": "approve",
                ],
            ],
        ]

        #expect(thread["model"] as? String == "gpt-6-luna")
        // Bunny tools never loosen the sandbox or the approval policy.
        #expect(thread["approvalPolicy"] as? String == "never")
        #expect(thread["sandbox"] as? String == "workspace-write")
        #expect(config == expectedConfig)
        #expect(turn["effort"] as? String == "high")
        #expect(echo["instructionsMentionBunnyTools"] as? Bool == true)
    }

    @Test func codexResumeSendsModelToolsAndEffort() async throws {
        var options = FakeCLI.options(cliPath: FakeCLI.codex)
        options.model = "gpt-6-sol"
        options.effort = "low"
        options.tools = Self.tools
        let echo = try await configEcho(options, resume: "th-old")
        let thread = try #require(echo["thread"] as? [String: Any])
        let turn = try #require(echo["turn"] as? [String: Any])
        let config = try #require(thread["config"] as? [String: Any])

        #expect(thread["threadId"] as? String == "th-old")
        #expect(thread["model"] as? String == "gpt-6-sol")
        #expect((config["mcp_servers"] as? [String: Any])?["bunny"] != nil)
        #expect(turn["effort"] as? String == "low")
    }

    @Test func codexAutoAcceptsBunnyElicitationOnly() async throws {
        let cases: [(String, String)] = [("ELICIT now", "elicitation: accept"), ("ELICIT_OTHER now", "elicitation error: -32601")]
        for autonomy in [AgentAutonomy.autonomous, .askFirst] {
            for (title, expected) in cases {
                var options = FakeCLI.options(cliPath: FakeCLI.codex, autonomy: autonomy)
                options.tools = Self.tools
                let runner = CodexRunner(options: options)
                let recorder = EventRecorder(runner)
                defer { runner.terminate() }

                runner.start(brief: makeBrief(title: title), harness: .codex, resumeSessionID: nil, initialMessage: nil)

                #expect(await recorder.waitForTurnFinished())
                #expect(recorder.events.turnsFinished.first?.text == expected)
                // Never surfaced to the user.
                #expect(recorder.events.questions.isEmpty)
            }
        }
    }

    @Test func codexRejectsBunnyElicitationWithoutTools() async throws {
        for autonomy in [AgentAutonomy.autonomous, .askFirst] {
            let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex, autonomy: autonomy))
            let recorder = EventRecorder(runner)
            defer { runner.terminate() }

            runner.start(brief: makeBrief(title: "ELICIT now"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

            #expect(await recorder.waitForTurnFinished())
            #expect(recorder.events.turnsFinished.first?.text == "elicitation error: -32601")
            #expect(recorder.events.questions.isEmpty)
        }
    }

    @Test func codexResumeUsesThreadResumeAndInitialMessage() async throws {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "Ignored"), harness: .codex, resumeSessionID: "th-old", initialMessage: "Answer: sqlite")

        #expect(await recorder.waitForTurnFinished())
        #expect(recorder.events.sessionIDs == ["th-old"])
        #expect(recorder.events.turnsFinished.first?.text == "done: Answer: sqlite")
    }

    @Test func codexFailedTurnThenFollowUpTurn() async throws {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "BADTURN"), harness: .codex, resumeSessionID: nil, initialMessage: nil)
        #expect(await recorder.waitForTurnFinished())
        let first = try #require(recorder.events.turnsFinished.first)
        #expect(!first.success)
        #expect(first.text == "kaput")

        runner.send("again")
        #expect(await recorder.waitForTurnFinished(count: 2))
        let second = recorder.events.turnsFinished.count > 1 ? recorder.events.turnsFinished[1].text : ""
        #expect(second == "done: again")
    }

    @Test func codexInterruptEndsRunningTurn() async throws {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "SLOW work"), harness: .codex, resumeSessionID: nil, initialMessage: nil)
        #expect(await recorder.wait { $0.activities.contains("working slowly") })

        let started = Date()
        runner.interrupt()

        #expect(await recorder.waitForTurnFinished(timeout: 4))
        let elapsed = Date().timeIntervalSince(started)
        let finished = try #require(recorder.events.turnsFinished.first)
        #expect(finished.text == "Interrupted")
        #expect(!finished.success)
        #expect(elapsed < 4)
        #expect(recorder.events.failures.isEmpty)
    }

    @Test func codexSendDuringRunningTurnIsQueuedUntilItCompletes() async throws {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: FakeCLI.codex))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "SLOW work"), harness: .codex, resumeSessionID: nil, initialMessage: nil)
        #expect(await recorder.wait { $0.activities.contains("working slowly") })

        // The fake rejects overlapping turn/start calls, so these must wait for the running turn.
        runner.send("next one")
        runner.send("last one")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(recorder.events.turnsFinished.isEmpty)
        runner.interrupt()

        #expect(await recorder.waitForTurnFinished(count: 3))
        let texts = recorder.events.turnsFinished.map(\.text)
        #expect(texts == ["Interrupted", "done: next one", "done: last one"])
    }

    @Test func codexMissingCLI() async {
        let runner = CodexRunner(options: FakeCLI.options(cliPath: "/nonexistent"))
        let recorder = EventRecorder(runner)

        runner.start(brief: makeBrief(title: "Anything"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.wait { !$0.exitCodes.isEmpty })
        #expect(recorder.events.failures.count == 1)
        #expect(recorder.events.sessionIDs.isEmpty)
    }

    @Test func codexThreadStartErrorFails() async throws {
        var options = FakeCLI.options(cliPath: FakeCLI.codex)
        options.environment["FAKE_CODEX_THREAD_ERROR"] = "1"
        let runner = CodexRunner(options: options)
        let recorder = EventRecorder(runner)

        runner.start(brief: makeBrief(title: "Anything"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

        // The runner reports the error and shuts the server down rather than leaving it idle.
        #expect(await recorder.wait { !$0.exitCodes.isEmpty })
        #expect(recorder.events.failures == ["thread boom"])
        #expect(recorder.events.sessionIDs.isEmpty)
        #expect(recorder.events.turnsFinished.isEmpty)
    }

    @Test func codexExitBeforeThreadStartFails() async throws {
        // A CLI that dies immediately (wrong argv for the fake) must surface as failed, never hang in running.
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-dead-codex-\(UUID().uuidString).sh")
        try "#!/bin/sh\necho 'codex: not logged in' >&2\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer { try? FileManager.default.removeItem(at: script) }

        let runner = CodexRunner(options: FakeCLI.options(cliPath: script.path))
        let recorder = EventRecorder(runner)

        runner.start(brief: makeBrief(title: "Anything"), harness: .codex, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.wait { !$0.exitCodes.isEmpty })
        #expect(recorder.events.failures.first?.contains("not logged in") == true)
        #expect(recorder.events.exitCodes == [1])
    }
}
