import Foundation

struct AgentRunOptions: Equatable, Sendable {
    var cliPath: String
    var autonomy: AgentAutonomy
    var environment: [String: String]
}

/// Drives one agent CLI session in the background. Use from the main thread only.
protocol AgentRunner: AnyObject {
    /// ALWAYS delivered on DispatchQueue.main, never synchronously from a method call.
    var onEvent: ((AgentEvent) -> Void)? { get set }
    var sessionID: String? { get }
    /// Starts a new session (resumeSessionID nil) or resumes one. `initialMessage` overrides the brief prompt as first user turn (used for resume-with-answer).
    func start(brief: AgentBrief, harness: AgentHarness, resumeSessionID: String?, initialMessage: String?)
    func answer(_ question: AgentQuestion, with answer: AgentAnswer)
    func send(_ text: String)
    func interrupt()
    func terminate()
}

/// Helpers shared by the runners.
enum AgentRunnerText {
    static let activityLimit = 120

    /// First non-empty line of `text`, trimmed and truncated to `activityLimit` characters.
    static func activityLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return truncated(line)
    }

    /// Truncates to `activityLimit` characters, ending in "…" when shortened.
    static func truncated(_ text: String) -> String {
        guard text.count > activityLimit else { return text }
        return String(text.prefix(activityLimit - 1)) + "…"
    }

    /// Failure message for a process that died mid-turn.
    static func exitFailure(code: Int32, stderrTail: String) -> String {
        stderrTail.isEmpty ? "exited with code \(code)" : stderrTail
    }

    /// Failure message for a CLI that could not be launched.
    static func launchFailure(harness: AgentHarness, path: String, error: Error) -> String {
        guard let error = error as? AgentProcessError else {
            return "Couldn't launch \(harness.displayName): \(error.localizedDescription)"
        }
        if case .notExecutable = error {
            return "\(harness.displayName) not found at \(path) — set its path in Settings."
        }
        return "Couldn't launch \(harness.displayName): \(error.message)"
    }

    /// Random alphanumeric id for Claude control requests.
    static func randomRequestID(length: Int = 13) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }
}
