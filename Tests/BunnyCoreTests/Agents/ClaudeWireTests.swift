import Foundation
import Testing
@testable import BunnyCore

struct ClaudeWireTests {
    @Test func parsesInitialized() {
        let line = Data(#"{"type":"system","subtype":"init","session_id":"abc","cwd":"/tmp"}"#.utf8)
        #expect(ClaudeWire.parse(line) == .initialized(sessionID: "abc"))
    }

    @Test func parsesAssistantTextBlocksJoinedByNewline() {
        let line = Data(#"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"},{"type":"text","text":"world"}]},"session_id":"abc"}"#.utf8)
        #expect(ClaudeWire.parse(line) == .assistantText("Hello\nworld"))
    }

    @Test func parsesAssistantBashToolUse() {
        let line = Data(#"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls -la"}}]},"session_id":"abc"}"#.utf8)
        #expect(ClaudeWire.parse(line) == .toolUse(name: "Bash", summary: "ls -la"))
    }

    @Test func parsesPermissionRequestWithInput() throws {
        let line = Data(#"{"type":"control_request","request_id":"req-1","request":{"subtype":"can_use_tool","tool_name":"AskUserQuestion","input":{"questions":[]},"tool_use_id":"tool-1"}}"#.utf8)

        let incoming = ClaudeWire.parse(line)
        guard case let .permissionRequest(requestID, toolName, input) = incoming else {
            Issue.record("Expected permission request, got \(incoming)")
            return
        }
        #expect(requestID == "req-1")
        #expect(toolName == "AskUserQuestion")
        let object = try #require(JSONSerialization.jsonObject(with: input) as? [String: Any])
        #expect((object["questions"] as? [Any])?.isEmpty == true)
    }

    @Test func parsesSuccessfulResult() {
        let line = Data(#"{"type":"result","subtype":"success","is_error":false,"result":"Done","session_id":"abc"}"#.utf8)
        #expect(ClaudeWire.parse(line) == .result(success: true, text: "Done", sessionID: "abc"))
    }

    @Test func parsesErrorResultWithoutResultField() {
        let line = Data(#"{"type":"result","subtype":"error_during_execution","is_error":true,"terminal_reason":"aborted_streaming","session_id":"abc"}"#.utf8)
        #expect(ClaudeWire.parse(line) == .result(success: false, text: "aborted_streaming", sessionID: "abc"))
    }

    @Test func parsesErrorListJoinedByNewline() {
        let line = Data(#"{"type":"result","subtype":"error_during_execution","is_error":true,"errors":["first","second"]}"#.utf8)
        #expect(ClaudeWire.parse(line) == .result(success: false, text: "first\nsecond", sessionID: nil))
    }

    @Test func ignoresGarbage() {
        #expect(ClaudeWire.parse(Data("not json".utf8)) == .ignored)
    }

    @Test func encodesUserMessage() throws {
        let object = try jsonObject(ClaudeWire.userMessage("hi"))
        let message = try #require(object["message"] as? [String: Any])
        let content = try #require(message["content"] as? [[String: Any]])

        #expect(object["type"] as? String == "user")
        #expect(message["role"] as? String == "user")
        #expect(content.first?["type"] as? String == "text")
        #expect(content.first?["text"] as? String == "hi")
    }

    @Test func encodesControlMessages() throws {
        let interrupt = try jsonObject(ClaudeWire.interrupt(requestID: "interrupt-1"))
        let interruptRequest = try #require(interrupt["request"] as? [String: Any])
        #expect(interrupt["type"] as? String == "control_request")
        #expect(interrupt["request_id"] as? String == "interrupt-1")
        #expect(interruptRequest["subtype"] as? String == "interrupt")

        let updatedInput = Data(#"{"command":"pwd"}"#.utf8)
        let allowed = try jsonObject(ClaudeWire.allow(requestID: "req-1", updatedInput: updatedInput))
        let allowedResponse = try responsePayload(allowed)
        #expect(allowedResponse["behavior"] as? String == "allow")
        #expect((allowedResponse["updatedInput"] as? [String: Any])?["command"] as? String == "pwd")

        let denied = try jsonObject(ClaudeWire.deny(requestID: "req-2", message: "No"))
        let deniedResponse = try responsePayload(denied)
        #expect(deniedResponse["behavior"] as? String == "deny")
        #expect(deniedResponse["message"] as? String == "No")
    }

    @Test func askUserQuestionBecomesChoicesAndAnswersPreserveInput() throws {
        let input = Data(#"{"questions":[{"question":"Q1","header":"Color","options":[{"label":"Blue","description":"Cool"}],"multiSelect":false},{"question":"Q2","header":"Letters","options":[{"label":"A","description":"First"},{"label":"B","description":"Second"}],"multiSelect":true}]}"#.utf8)
        let question = ClaudeWire.question(requestID: "req-1", toolName: "AskUserQuestion", input: input)

        #expect(question.kind == .choices)
        #expect(question.requestID == "req-1")
        #expect(question.rawInput == input)
        #expect(question.items.map(\.key) == ["Q1", "Q2"])
        #expect(question.items.map(\.allowsOther) == [true, true])
        #expect(question.items.first?.options.first == AgentQuestionOption(label: "Blue", detail: "Cool"))
        #expect(question.items.last?.multiSelect == true)

        let answer = AgentAnswer(selections: ["Q1": ["Blue"], "Q2": ["A", "B"]], approved: nil)
        let answered = try jsonObject(ClaudeWire.answeredInput(for: question, answer: answer))
        let answers = try #require(answered["answers"] as? [String: String])
        let questions = try #require(answered["questions"] as? [[String: Any]])

        #expect(answers["Q1"] == "Blue")
        #expect(answers["Q2"] == "A, B")
        #expect(questions.count == 2)
        #expect(questions.first?["question"] as? String == "Q1")
        #expect(questions.last?["multiSelect"] as? Bool == true)
    }

    @Test func bashQuestionBecomesApproval() {
        let input = Data(#"{"command":"ls -la"}"#.utf8)
        let question = ClaudeWire.question(requestID: "req-2", toolName: "Bash", input: input)

        #expect(question.kind == .approval)
        #expect(question.approvalTitle == "Use Bash")
        #expect(question.approvalDetail == "ls -la")
        #expect(question.requestID == "req-2")
        #expect(question.rawInput == input)
    }

    private func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func responsePayload(_ object: [String: Any]) throws -> [String: Any] {
        let envelope = try #require(object["response"] as? [String: Any])
        return try #require(envelope["response"] as? [String: Any])
    }
}
