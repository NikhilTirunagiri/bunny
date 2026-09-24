import Foundation

/// Extracts and strips Bunny's inline markers (`<bunny-question>`, `<bunny-subtasks-done>`) from Codex's turn text. Pure, Foundation-only.
enum AgentMarkers {
    private struct MarkerQuestionJSON: Decodable {
        let question: String
        let options: [String]?
    }

    static func extractQuestion(from text: String) -> (text: String, question: AgentQuestion?) {
        guard let regex = try? NSRegularExpression(pattern: "<bunny-question>(.*?)</bunny-question>", options: [.dotMatchesLineSeparators]) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard let last = matches.last else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }

        let strippedText = nsText.replacingCharacters(in: last.range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = nsText.substring(with: last.range(at: 1))

        guard let data = payload.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(MarkerQuestionJSON.self, from: data) else {
            return (strippedText, nil)
        }

        let question: AgentQuestion
        if let options = parsed.options, !options.isEmpty {
            let item = AgentQuestionItem(
                key: "answer",
                header: nil,
                question: parsed.question,
                options: options.map { AgentQuestionOption(label: $0, detail: nil) },
                multiSelect: false,
                allowsOther: true
            )
            question = AgentQuestion(kind: .choices, items: [item], approvalTitle: nil, approvalDetail: nil, requestID: nil, method: nil, rawInput: nil)
        } else {
            let item = AgentQuestionItem(
                key: "answer",
                header: nil,
                question: parsed.question,
                options: [],
                multiSelect: false,
                allowsOther: false
            )
            question = AgentQuestion(kind: .freeform, items: [item], approvalTitle: nil, approvalDetail: nil, requestID: nil, method: nil, rawInput: nil)
        }

        return (strippedText, question)
    }

    static func extractCompletedSubtasks(from text: String) -> (text: String, numbers: [Int]) {
        guard let regex = try? NSRegularExpression(pattern: "<bunny-subtasks-done>(.*?)</bunny-subtasks-done>", options: [.dotMatchesLineSeparators]) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }

        let strippedText = nsText.replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = nsText.substring(with: match.range(at: 1))
        let numbers = payload.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }

        return (strippedText, numbers)
    }
}
