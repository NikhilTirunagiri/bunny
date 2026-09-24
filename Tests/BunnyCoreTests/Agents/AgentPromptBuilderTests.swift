import Testing
import Foundation
@testable import BunnyCore

struct AgentPromptBuilderTests {
    @Test func promptIncludesAllSections() {
        let now = ISO8601DateFormatter().date(from: "2026-09-24T10:00:00Z")!
        let deadline = now.addingTimeInterval(25 * 60)
        let brief = AgentBrief(
            title: "Fix login",
            description: "Users get logged out.",
            subtasks: [
                AgentBrief.Subtask(title: "Repro", done: false),
                AgentBrief.Subtask(title: "Patch", done: true),
            ],
            shelf: [
                AgentBrief.ShelfEntry(path: "/Users/n/code/app", isDirectory: true),
                AgentBrief.ShelfEntry(path: "/Users/n/notes.md", isDirectory: false),
            ],
            deadline: deadline,
            workingDirectory: "/Users/n/code/app",
            extraDirectories: []
        )
        let expected = """
        # Task: Fix login

        Users get logged out.

        ## Subtasks
        - [ ] 1. Repro
        - [x] 2. Patch

        ## Files and folders
        - /Users/n/code/app (folder)
        - /Users/n/notes.md

        ## Time budget
        You have 25 minutes (until 10:25). Prioritize finishing within it.
        """
        #expect(AgentPromptBuilder.prompt(for: brief, now: now, timeZone: TimeZone(identifier: "UTC")!) == expected)
    }

    @Test func promptMinimal() {
        let brief = AgentBrief(
            title: "X",
            description: "",
            subtasks: [],
            shelf: [],
            deadline: nil,
            workingDirectory: "/tmp",
            extraDirectories: []
        )
        #expect(AgentPromptBuilder.prompt(for: brief, now: Date()) == "# Task: X\n\n(no description)")
    }

    @Test func appendixMentionsHarnessMechanism() {
        let claude = AgentPromptBuilder.systemAppendix(for: .claudeCode)
        let codex = AgentPromptBuilder.systemAppendix(for: .codex)
        #expect(claude.contains("AskUserQuestion"))
        #expect(codex.contains("<bunny-question>"))
        #expect(claude.contains("<bunny-subtasks-done>"))
        #expect(codex.contains("<bunny-subtasks-done>"))
    }
}
