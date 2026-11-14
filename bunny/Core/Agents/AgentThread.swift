import Foundation

/// The short conversation kept with a note: what the user sent from Bunny and the agent's turn-final
/// replies (no tool output, no activity). Stored as JSON in `BunnyTask.agentThreadData`. Pure, Foundation-only.
enum AgentThread {
    enum Role: String, Codable, Sendable { case user, agent }

    struct Entry: Codable, Equatable, Sendable {
        var role: Role
        var text: String
        var date: Date
    }

    static let maxEntries = 40
    static let maxTextLength = 2_000
    /// An agent message longer than this folds behind "Show more".
    static let foldedLines = 6

    static func entries(from data: Data?) -> [Entry] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    /// `data` with one more entry: the text trimmed and cut to `maxTextLength`, the oldest entries
    /// dropped beyond `maxEntries`. Blank text adds nothing.
    static func appending(_ role: Role, _ text: String, at date: Date, to data: Data?) -> Data? {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return data }
        if text.count > maxTextLength { text = String(text.prefix(maxTextLength - 1)) + "…" }
        let all = entries(from: data) + [Entry(role: role, text: text, date: date)]
        return try? JSONEncoder().encode(Array(all.suffix(maxEntries)))
    }

    /// How many entries sit behind "Show N earlier messages". Shown without it: the last agent message,
    /// the user messages after the agent message before it, and anything after.
    static func earlierCount(_ entries: [Entry]) -> Int {
        guard let last = entries.lastIndex(where: { $0.role == .agent }),
              let previous = entries[..<last].lastIndex(where: { $0.role == .agent }) else { return 0 }
        return previous + 1
    }

    /// When the agent last said something.
    static func lastAgentDate(_ entries: [Entry]) -> Date? {
        entries.last { $0.role == .agent }?.date
    }

    /// Too long to show whole: more than `foldedLines` lines, or about that much wrapped text.
    static func isLong(_ text: String) -> Bool {
        text.count > 300 || text.split(separator: "\n", omittingEmptySubsequences: false).count > foldedLines
    }
}

/// Where a message typed in Bunny goes (v3 spec §7 "Messaging").
enum AgentMessageRule {
    enum Delivery: Equatable, Sendable {
        /// A turn is running: hold the message and send it on the same runner when the turn ends.
        /// (Sent mid-turn, either CLI would start another turn the supervisor no longer waits for.)
        case whenTurnEnds
        /// No process: resume the session with the message as the next user turn.
        case resumeSession
        /// No session to continue, or a question is pending (the question form is the input).
        case unavailable
    }

    static func delivery(state: AgentRunState, hasSession: Bool) -> Delivery {
        switch state {
        case .running: return .whenTurnEnds
        case .needsInput, .idle: return .unavailable
        case .replied, .finished, .failed, .stopped, .handedOff: return hasSession ? .resumeSession : .unavailable
        }
    }

    /// The held messages as one user turn, in the order they were typed; nil when there are none.
    static func combined(_ queued: [String]) -> String? {
        queued.isEmpty ? nil : queued.joined(separator: "\n\n")
    }
}
