import Testing
import Foundation
@testable import BunnyCore

struct AgentTypesTests {
    @Test func answerSummaryOneItemMultiSelection() {
        let question = AgentQuestion(
            kind: .choices,
            items: [AgentQuestionItem(key: "answer", header: nil, question: "Pick", options: [], multiSelect: true, allowsOther: true)],
            approvalTitle: nil, approvalDetail: nil, requestID: nil, method: nil, rawInput: nil
        )
        let answer = AgentAnswer(selections: ["answer": ["A", "B"]], approved: nil)
        #expect(answer.summary(for: question) == "A, B")
    }

    @Test func answerSummaryApproval() {
        let question = AgentQuestion(
            kind: .approval,
            items: [],
            approvalTitle: "Run command", approvalDetail: "ls -la", requestID: nil, method: nil, rawInput: nil
        )
        let answer = AgentAnswer(selections: [:], approved: true)
        #expect(answer.summary(for: question) == "Allowed")

        let denied = AgentAnswer(selections: [:], approved: false)
        #expect(denied.summary(for: question) == "Denied")
    }

    @Test func questionRoundTripsThroughJSON() throws {
        let question = AgentQuestion(
            kind: .choices,
            items: [AgentQuestionItem(key: "answer", header: "Header", question: "Pick one", options: [AgentQuestionOption(label: "A", detail: "detail")], multiSelect: false, allowsOther: true)],
            approvalTitle: "Run command",
            approvalDetail: "ls -la",
            requestID: "req-1",
            method: "applyPatchApproval",
            rawInput: Data("{\"x\":1}".utf8)
        )
        let encoded = try JSONEncoder().encode(question)
        let decoded = try JSONDecoder().decode(AgentQuestion.self, from: encoded)
        #expect(decoded == question)
    }

    @Test func harnessDisplay() {
        #expect(AgentHarness.claudeCode.displayName == "Claude Code")
        #expect(AgentHarness.claudeCode.symbolName == "sparkle")
        #expect(AgentHarness.codex.displayName == "Codex")
        #expect(AgentHarness.codex.symbolName == "chevron.left.forwardslash.chevron.right")
    }

    @Test func runStateLabelsAndActivity() {
        #expect(AgentRunState.idle.label == "Idle")
        #expect(AgentRunState.running.label == "Working…")
        #expect(AgentRunState.needsInput.label == "Needs your input")
        #expect(AgentRunState.finished.label == "Done")
        #expect(AgentRunState.failed.label == "Failed")
        #expect(AgentRunState.stopped.label == "Stopped")
        #expect(AgentRunState.handedOff.label == "Opened in app")
        #expect(AgentRunState.running.isActive)
        #expect(AgentRunState.needsInput.isActive)
        #expect(!AgentRunState.idle.isActive)
        #expect(!AgentRunState.finished.isActive)
    }

    @Test func openInAppDisplay() {
        #expect(OpenInApp.terminal.displayName == "Terminal")
        #expect(OpenInApp.ghostty.displayName == "Ghostty")
        #expect(OpenInApp.vscode.displayName == "VS Code")
        #expect(OpenInApp.cursor.displayName == "Cursor")
    }
}
