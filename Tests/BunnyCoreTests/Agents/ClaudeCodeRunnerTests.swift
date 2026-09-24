import Foundation
import Testing
@testable import BunnyCore

@MainActor
struct ClaudeCodeRunnerTests {
    @Test func claudeHappyPath() async {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "Tidy the desk"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.waitForTurnFinished())
        let events = recorder.events
        #expect(events.sessionIDs == ["sess-1"])
        #expect(events.activities.contains("working"))
        let finished = events.turnsFinished.first
        #expect(finished?.success == true)
        #expect(finished?.text.hasPrefix("done: # Task: Tidy the desk") == true)
        #expect(runner.sessionID == "sess-1")
        #expect(events.failures.isEmpty)
    }

    @Test func claudeAskAndAnswer() async throws {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "ASK me"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.wait { !$0.questions.isEmpty })
        let question = try #require(recorder.events.questions.first)
        #expect(question.kind == .choices)
        #expect(question.requestID == "r1")
        #expect(question.items.map(\.key) == ["Pick one?"])
        #expect(question.items.first?.options.map(\.label) == ["A", "B"])

        runner.answer(question, with: AgentAnswer(selections: ["Pick one?": ["B"]], approved: nil))

        #expect(await recorder.waitForTurnFinished())
        let finished = try #require(recorder.events.turnsFinished.first)
        #expect(finished.success)
        #expect(finished.text.contains("Pick one?"))
        #expect(finished.text.contains("\"B\""))
    }

    @Test func claudeApprovalAllowAndDeny() async throws {
        for approved in [true, false] {
            let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude, autonomy: .askFirst))
            let recorder = EventRecorder(runner)
            defer { runner.terminate() }

            runner.start(brief: makeBrief(title: "APPROVE this"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

            #expect(await recorder.wait { !$0.questions.isEmpty })
            let question = try #require(recorder.events.questions.first)
            #expect(question.kind == .approval)
            #expect(question.requestID == "r2")

            runner.answer(question, with: AgentAnswer(selections: [:], approved: approved))

            #expect(await recorder.waitForTurnFinished())
            let text = recorder.events.turnsFinished.first?.text ?? ""
            if approved {
                #expect(text.contains("approval: allow"))
                #expect(text.contains("rm -rf build"))
            } else {
                #expect(text.contains("approval: deny"))
            }
        }
    }

    @Test func claudeProcessFailure() async throws {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude))
        let recorder = EventRecorder(runner)

        runner.start(brief: makeBrief(title: "FAIL now"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.wait { !$0.exitCodes.isEmpty })
        let events = recorder.events
        let failure = try #require(events.failures.first)
        #expect(failure.contains("boom"))
        #expect(events.exitCodes == [3])
        let failedIndex = events.firstIndex { if case .failed = $0 { return true } else { return false } }
        let exitedIndex = events.firstIndex { if case .exited = $0 { return true } else { return false } }
        let failedBeforeExit = (failedIndex ?? Int.max) < (exitedIndex ?? Int.min)
        #expect(failedBeforeExit)
        #expect(events.turnsFinished.isEmpty)
    }

    @Test func claudeMissingCLI() async {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: "/nonexistent"))
        let recorder = EventRecorder(runner)

        runner.start(brief: makeBrief(title: "Anything"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

        // Events are never delivered synchronously from start().
        #expect(recorder.events.isEmpty)
        #expect(await recorder.wait { !$0.exitCodes.isEmpty })
        #expect(recorder.events.failures.count == 1)
        #expect(recorder.events.failures.first?.contains("/nonexistent") == true)
        // Calls after a failed launch are harmless no-ops.
        runner.send("hello")
        runner.interrupt()
        runner.terminate()
    }

    @Test func claudeArgvIncludesAddDirAndMode() async throws {
        let extra = "/tmp/bunny extra dir"
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude, autonomy: .askFirst))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "Args", extraDirectories: [extra]), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)

        #expect(await recorder.waitForTurnFinished())
        let text = try #require(recorder.events.turnsFinished.first?.text)
        let argvJSON = try #require(text.components(separatedBy: " | argv=").last)
        let argv = try #require(JSONSerialization.jsonObject(with: Data(argvJSON.utf8)) as? [String])

        let expectedPrefix = [
            "-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
            "--permission-prompt-tool", "stdio", "--permission-mode", "acceptEdits", "--append-system-prompt",
        ]
        let prefix = Array(argv.prefix(expectedPrefix.count))
        #expect(prefix == expectedPrefix)
        let appendixIndex = expectedPrefix.count
        let appendix = argv.count > appendixIndex ? argv[appendixIndex] : ""
        #expect(appendix == AgentPromptBuilder.systemAppendix(for: .claudeCode))
        let tail = Array(argv.dropFirst(expectedPrefix.count + 1))
        #expect(tail == ["--add-dir", extra])
        #expect(!argv.contains("--resume"))
    }

    @Test func claudeResumeUsesResumeFlagAndInitialMessage() async throws {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "Ignored title"), harness: .claudeCode, resumeSessionID: "sess-1", initialMessage: "Answer: B")

        #expect(runner.sessionID == "sess-1")
        #expect(await recorder.waitForTurnFinished())
        let text = try #require(recorder.events.turnsFinished.first?.text)
        #expect(text.hasPrefix("done: Answer: B |"))
        #expect(text.contains(#""--permission-mode", "bypassPermissions""#))
        #expect(text.contains(#""--resume", "sess-1""#))
    }

    @Test func claudeFollowUpTurnAndInterrupt() async throws {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude))
        let recorder = EventRecorder(runner)
        defer { runner.terminate() }

        runner.start(brief: makeBrief(title: "First"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)
        #expect(await recorder.waitForTurnFinished())

        runner.send("Second")
        #expect(await recorder.waitForTurnFinished(count: 2))
        let second = recorder.events.turnsFinished.count > 1 ? recorder.events.turnsFinished[1].text : ""
        #expect(second.hasPrefix("done: Second |"))
        // system/init is re-emitted per turn by the real CLI; sessionStarted fires once per new id.
        #expect(recorder.events.sessionIDs == ["sess-1"])

        runner.interrupt()
        #expect(await recorder.waitForTurnFinished(count: 3))
        let third = recorder.events.turnsFinished.count > 2 ? recorder.events.turnsFinished[2] : (text: "", success: true)
        #expect(!third.success)
        #expect(third.text.hasPrefix("interrupted"))
    }

    @Test func claudeTerminateDoesNotReportFailure() async {
        let runner = ClaudeCodeRunner(options: FakeCLI.options(cliPath: FakeCLI.claude))
        let recorder = EventRecorder(runner)

        runner.start(brief: makeBrief(title: "ASK and wait"), harness: .claudeCode, resumeSessionID: nil, initialMessage: nil)
        #expect(await recorder.wait { !$0.questions.isEmpty })

        runner.terminate()
        #expect(await recorder.wait { !$0.exitCodes.isEmpty })
        #expect(recorder.events.failures.isEmpty)
    }
}
