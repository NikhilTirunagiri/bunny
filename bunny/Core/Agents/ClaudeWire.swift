import Foundation

enum ClaudeWire {
    enum Incoming: Equatable {
        case initialized(sessionID: String)
        case assistantText(String)
        case toolUse(name: String, summary: String)
        case permissionRequest(requestID: String, toolName: String, input: Data)
        case result(success: Bool, text: String, sessionID: String?)
        case ignored
    }

    static func parse(_ line: Data) -> Incoming {
        guard let object = jsonObject(line), let type = object["type"] as? String else {
            return .ignored
        }

        switch type {
        case "system":
            guard object["subtype"] as? String == "init",
                  let sessionID = object["session_id"] as? String else {
                return .ignored
            }
            return .initialized(sessionID: sessionID)

        case "assistant":
            guard let message = object["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]] else {
                return .ignored
            }

            let text = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            if !text.isEmpty {
                return .assistantText(text.joined(separator: "\n"))
            }

            guard let tool = content.first(where: { $0["type"] as? String == "tool_use" }),
                  let name = tool["name"] as? String else {
                return .ignored
            }
            let input = tool["input"] as? [String: Any] ?? [:]
            return .toolUse(name: name, summary: toolSummary(name: name, input: input))

        case "control_request":
            guard let requestID = object["request_id"] as? String,
                  let request = object["request"] as? [String: Any],
                  request["subtype"] as? String == "can_use_tool",
                  let toolName = request["tool_name"] as? String,
                  let input = request["input"] as? [String: Any],
                  let inputData = encoded(input) else {
                return .ignored
            }
            return .permissionRequest(requestID: requestID, toolName: toolName, input: inputData)

        case "result":
            guard let subtype = object["subtype"] as? String,
                  let isError = object["is_error"] as? Bool else {
                return .ignored
            }
            let success = subtype == "success" && !isError
            let text: String
            if success {
                text = object["result"] as? String ?? ""
            } else if let errors = object["errors"] as? [String], !errors.isEmpty {
                text = errors.joined(separator: "\n")
            } else {
                text = object["terminal_reason"] as? String ?? ""
            }
            return .result(
                success: success,
                text: text,
                sessionID: object["session_id"] as? String
            )

        default:
            return .ignored
        }
    }

    static func userMessage(_ text: String) -> Data {
        encode([
            "type": "user",
            "message": [
                "role": "user",
                "content": [["type": "text", "text": text]],
            ],
        ])
    }

    static func interrupt(requestID: String) -> Data {
        encode([
            "type": "control_request",
            "request_id": requestID,
            "request": ["subtype": "interrupt"],
        ])
    }

    static func allow(requestID: String, updatedInput: Data) -> Data {
        encode(controlResponse(
            requestID: requestID,
            response: [
                "behavior": "allow",
                "updatedInput": jsonObject(updatedInput) ?? [:],
            ]
        ))
    }

    static func deny(requestID: String, message: String) -> Data {
        encode(controlResponse(
            requestID: requestID,
            response: [
                "behavior": "deny",
                "message": message,
            ]
        ))
    }

    /// AskUserQuestion becomes a choices question; every other tool becomes an approval.
    static func question(requestID: String, toolName: String, input: Data) -> AgentQuestion {
        guard toolName == "AskUserQuestion" else {
            let inputObject = jsonObject(input) ?? [:]
            return AgentQuestion(
                kind: .approval,
                items: [],
                approvalTitle: "Use \(toolName)",
                approvalDetail: toolSummary(name: toolName, input: inputObject),
                requestID: requestID,
                method: nil,
                rawInput: input
            )
        }

        let inputObject = jsonObject(input) ?? [:]
        let rawQuestions = inputObject["questions"] as? [[String: Any]] ?? []
        let items = rawQuestions.compactMap { raw -> AgentQuestionItem? in
            guard let text = raw["question"] as? String else { return nil }
            let rawOptions = raw["options"] as? [[String: Any]] ?? []
            let options = rawOptions.compactMap { option -> AgentQuestionOption? in
                guard let label = option["label"] as? String else { return nil }
                return AgentQuestionOption(label: label, detail: option["description"] as? String)
            }
            return AgentQuestionItem(
                key: text,
                header: raw["header"] as? String,
                question: text,
                options: options,
                multiSelect: raw["multiSelect"] as? Bool ?? false,
                allowsOther: true
            )
        }

        return AgentQuestion(
            kind: .choices,
            items: items,
            approvalTitle: nil,
            approvalDetail: nil,
            requestID: requestID,
            method: nil,
            rawInput: input
        )
    }

    /// Adds answers keyed by exact question text to the original AskUserQuestion input.
    static func answeredInput(for question: AgentQuestion, answer: AgentAnswer) -> Data {
        var input = question.rawInput.flatMap { jsonObject($0) } ?? [:]
        var answers: [String: String] = [:]
        for item in question.items {
            answers[item.key] = (answer.selections[item.key] ?? []).joined(separator: ", ")
        }
        input["answers"] = answers
        return encode(input)
    }

    private static func controlResponse(requestID: String, response: [String: Any]) -> [String: Any] {
        [
            "type": "control_response",
            "response": [
                "subtype": "success",
                "request_id": requestID,
                "response": response,
            ],
        ]
    }

    private static func toolSummary(name: String, input: [String: Any]) -> String {
        switch name {
        case "Bash":
            return input["command"] as? String ?? ""
        case "Edit", "Write", "Read":
            return input["file_path"] as? String ?? ""
        default:
            return ""
        }
    }

    private static func jsonObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func encoded(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func encode(_ object: [String: Any]) -> Data {
        encoded(object) ?? Data()
    }
}
