import Testing
import Foundation
@testable import BunnyCore

struct AgentThreadTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)

    private func thread(_ roles: [AgentThread.Role]) -> [AgentThread.Entry] {
        roles.enumerated().map { AgentThread.Entry(role: $1, text: "m\($0)", date: t0.addingTimeInterval(Double($0))) }
    }

    @Test func appendsAndDecodes() {
        var data = AgentThread.appending(.user, "  hello \n", at: t0, to: nil)
        data = AgentThread.appending(.agent, "hi", at: t0.addingTimeInterval(1), to: data)
        let entries = AgentThread.entries(from: data)
        #expect(entries.map(\.role) == [.user, .agent])
        #expect(entries.map(\.text) == ["hello", "hi"])
        #expect(AgentThread.lastAgentDate(entries) == t0.addingTimeInterval(1))
    }

    @Test func blankTextAddsNothing() {
        #expect(AgentThread.appending(.user, " \n ", at: t0, to: nil) == nil)
    }

    @Test func capsEntriesAndTextLength() {
        var data: Data?
        for index in 0..<45 { data = AgentThread.appending(.user, "m\(index)", at: t0, to: data) }
        let entries = AgentThread.entries(from: data)
        #expect(entries.count == AgentThread.maxEntries)
        #expect(entries.first?.text == "m5")
        #expect(entries.last?.text == "m44")

        let long = AgentThread.entries(from: AgentThread.appending(.agent, String(repeating: "x", count: 5_000), at: t0, to: nil))
        #expect(long.first?.text.count == AgentThread.maxTextLength)
        #expect(long.first?.text.hasSuffix("…") == true)
    }

    @Test func garbageDataIsAnEmptyThread() {
        #expect(AgentThread.entries(from: Data("nope".utf8)).isEmpty)
        #expect(AgentThread.entries(from: nil).isEmpty)
    }

    @Test func lastExchangeIsVisible() {
        // No agent message, or only one: everything shows.
        #expect(AgentThread.earlierCount(thread([.user, .user])) == 0)
        #expect(AgentThread.earlierCount(thread([.user, .agent, .user])) == 0)
        // agent, user, user, agent, user: the first agent message is earlier.
        #expect(AgentThread.earlierCount(thread([.agent, .user, .user, .agent, .user])) == 1)
        // user, agent, user, agent, user, agent: everything up to the second agent message is earlier.
        #expect(AgentThread.earlierCount(thread([.user, .agent, .user, .agent, .user, .agent])) == 4)
    }

    @Test func longText() {
        #expect(!AgentThread.isLong("Done. Two files changed."))
        #expect(AgentThread.isLong(String(repeating: "word ", count: 80)))
        #expect(AgentThread.isLong((1...7).map { "line \($0)" }.joined(separator: "\n")))
    }
}

struct AgentMessageRuleTests {
    @Test func midTurnMessagesWaitForTheTurnToEnd() {
        #expect(AgentMessageRule.delivery(state: .running, hasSession: true) == .whenTurnEnds)
        #expect(AgentMessageRule.delivery(state: .running, hasSession: false) == .whenTurnEnds)
    }

    @Test func noProcessResumesTheSession() {
        for state in [AgentRunState.replied, .finished, .failed, .stopped, .handedOff] {
            #expect(AgentMessageRule.delivery(state: state, hasSession: true) == .resumeSession)
            #expect(AgentMessageRule.delivery(state: state, hasSession: false) == .unavailable)
        }
    }

    @Test func aPendingQuestionIsTheInput() {
        #expect(AgentMessageRule.delivery(state: .needsInput, hasSession: true) == .unavailable)
        #expect(AgentMessageRule.delivery(state: .idle, hasSession: false) == .unavailable)
    }

    @Test func heldMessagesBecomeOneTurnInOrder() {
        #expect(AgentMessageRule.combined([]) == nil)
        #expect(AgentMessageRule.combined(["first"]) == "first")
        #expect(AgentMessageRule.combined(["first", "second"]) == "first\n\nsecond")
    }
}

struct AgentPanelRulesTests {
    @Test func aNoteCanBeHandedOffAgainUnlessARunIsActive() {
        for state in [AgentRunState.idle, .replied, .finished, .failed, .stopped, .handedOff] {
            #expect(AgentPanelRules.canHandOff(state: state))
        }
        #expect(!AgentPanelRules.canHandOff(state: .running))
        #expect(!AgentPanelRules.canHandOff(state: .needsInput))
    }

    @Test func aHandedOffSessionStillTakesMessages() {
        // Whatever became of the app or terminal it was opened in: a message resumes it in the background.
        #expect(AgentMessageRule.delivery(state: .handedOff, hasSession: true) == .resumeSession)
    }

    @Test func statusPhrases() {
        #expect(AgentPanelRules.statusPhrase(agent: "Codex", state: .running) == "Codex is working")
        #expect(AgentPanelRules.statusPhrase(agent: "Codex", state: .needsInput) == "Codex has a question")
        #expect(AgentPanelRules.statusPhrase(agent: "Claude Code", state: .replied) == "Claude Code replied")
        #expect(AgentPanelRules.statusPhrase(agent: "Claude Code", state: .finished) == "Claude Code finished")
        #expect(AgentPanelRules.statusPhrase(agent: "Codex", state: .stopped) == "Stopped")
        #expect(AgentPanelRules.statusPhrase(agent: "Codex", state: .handedOff, opened: "Opened in Ghostty") == "Opened in Ghostty")
        #expect(AgentPanelRules.statusPhrase(agent: "Codex", state: .handedOff, opened: "Opening…") == "Opened in app")
        #expect(AgentPanelRules.statusPhrase(agent: "Codex", state: .handedOff, opened: "Opened in Terminal\nkitty wasn't found.") == "Opened in Terminal")
        #expect(AgentPanelRules.openedNote(activity: "Opened in Terminal\nkitty wasn't found.") == "kitty wasn't found.")
        #expect(AgentPanelRules.openedNote(activity: "Opened in Ghostty") == nil)
        #expect(AgentPanelRules.openedNote(activity: "Opening…") == nil)
        #expect(AgentPanelRules.openedNote(activity: "Couldn't open the app — resume command copied: x") == "Couldn't open the app — resume command copied: x")
    }

    @Test func failureSentences() {
        func sentence(_ raw: String) -> String { AgentPanelRules.failureSentence(raw: raw, agent: "Claude Code") }
        #expect(sentence("Claude Code not found — set its path in Settings → Agents.") == "Claude Code was not found on this Mac.")
        #expect(sentence("Claude Code not found at /usr/local/bin/claude — set its path in Settings.") == "Claude Code was not found on this Mac.")
        #expect(sentence("Couldn't launch Claude Code: The file doesn't exist.") == "Claude Code could not start.")
        #expect(sentence("error: unknown option '--effort'") == "Claude Code could not start.")
        #expect(sentence("Agent exited unexpectedly") == "Claude Code stopped unexpectedly.")
        #expect(sentence("exited with code 137") == "Claude Code stopped unexpectedly.")
        #expect(sentence("zsh: permission denied: ./run.sh") == "Claude Code was not allowed to do that (permission denied).")
        #expect(sentence("Interrupted") == "The run was interrupted.")
        #expect(sentence("Something odd") == "The run failed.")
        #expect(sentence("") == "The run failed.")
    }

    @Test func whichPartOpens() {
        let said = Date(timeIntervalSince1970: 100)
        #expect(AgentPanelRules.opensAgent(state: .running, lastAgentMessage: nil, lastSeen: nil))
        #expect(AgentPanelRules.opensAgent(state: .needsInput, lastAgentMessage: nil, lastSeen: said))
        #expect(AgentPanelRules.opensAgent(state: .replied, lastAgentMessage: said, lastSeen: nil))
        #expect(!AgentPanelRules.opensAgent(state: .replied, lastAgentMessage: said, lastSeen: said))
        #expect(AgentPanelRules.opensAgent(state: .finished, lastAgentMessage: said, lastSeen: nil))
        #expect(AgentPanelRules.opensAgent(state: .finished, lastAgentMessage: said, lastSeen: said.addingTimeInterval(-1)))
        #expect(!AgentPanelRules.opensAgent(state: .finished, lastAgentMessage: said, lastSeen: said))
        #expect(!AgentPanelRules.opensAgent(state: .failed, lastAgentMessage: nil, lastSeen: nil))
    }

    @Test func elapsed() {
        #expect(AgentPanelRules.elapsed(95) == "01:35")
        #expect(AgentPanelRules.elapsed(3_723) == "1:02:03")
        #expect(AgentPanelRules.elapsed(-4) == "00:00")
    }
}
