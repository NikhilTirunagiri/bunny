import Foundation

/// What the note side says about an agent run (v3 spec §7 "State in the note side", "Note/agent fold").
/// Pure, Foundation-only.
enum AgentPanelRules {
    /// The status line: "<Agent> is working", "<Agent> has a question", … `opened` is the activity
    /// text of a handed-off session ("Opened in Terminal", with an optional note on a second line).
    static func statusPhrase(agent: String, state: AgentRunState, opened: String = "") -> String {
        switch state {
        case .idle: return agent
        case .running: return "\(agent) is working"
        case .needsInput: return "\(agent) has a question"
        case .replied: return "\(agent) replied"
        case .finished: return "\(agent) finished"
        case .failed: return "\(agent) failed"
        case .stopped: return "Stopped"
        case .handedOff:
            let first = opened.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
            return first.hasPrefix("Opened in ") ? first : "Opened in app"
        }
    }

    /// What a handed-off session shows under its status line: the note after "Opened in <app>" (why a
    /// fallback was used), or the whole activity when nothing was opened (the copied resume command).
    static func openedNote(activity: String) -> String? {
        guard activity.hasPrefix("Opened in ") else {
            return activity.isEmpty || activity == "Opening…" ? nil : activity
        }
        let rest = activity.split(separator: "\n", omittingEmptySubsequences: true).dropFirst().joined(separator: " ")
        return rest.isEmpty ? nil : rest
    }

    /// Whether the note can be handed off (again): always, unless a run is active. A session that
    /// was opened in an app, replied, finished, failed or was stopped never blocks a new hand-off:
    /// Bunny cannot see what became of an app or terminal it opened.
    static func canHandOff(state: AgentRunState) -> Bool {
        !state.isActive
    }

    /// One plain sentence for a failed run, from the raw error text.
    static func failureSentence(raw: String, agent: String) -> String {
        let text = raw.lowercased()
        func has(_ parts: String...) -> Bool { parts.contains { text.contains($0) } }
        if has("not found", "no such file", "enoent") && has(agent.lowercased(), "command", "cli", "executable", "path") {
            return "\(agent) was not found on this Mac."
        }
        if has("permission denied", "operation not permitted", "eacces", "not permitted") {
            return "\(agent) was not allowed to do that (permission denied)."
        }
        if has("couldn't launch", "could not launch", "config", "invalid", "unknown option", "unknown argument",
               "unexpected argument", "did not return a thread id", "not logged in", "login", "api key", "unauthorized") {
            return "\(agent) could not start."
        }
        if has("exited", "exit code", "signal", "status 1", "crash") {
            return "\(agent) stopped unexpectedly."
        }
        if has("interrupted") { return "The run was interrupted." }
        return "The run failed."
    }

    /// Which part of the note side is open when a note with agent state is shown: the agent while a
    /// run is active, or when it said something the user has not seen; the note otherwise.
    static func opensAgent(state: AgentRunState, lastAgentMessage: Date?, lastSeen: Date?) -> Bool {
        if state.isActive { return true }
        guard let lastAgentMessage else { return false }
        return lastSeen.map { lastAgentMessage > $0 } ?? true
    }

    /// "01:35", or "1:02:03" from an hour on.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }
}
