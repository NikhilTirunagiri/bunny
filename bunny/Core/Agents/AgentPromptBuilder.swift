import Foundation

/// Builds the first user message and system-prompt appendix handed to an agent CLI. Pure, Foundation-only.
enum AgentPromptBuilder {
    static func prompt(for brief: AgentBrief, now: Date, timeZone: TimeZone = .current) -> String {
        var sections: [String] = []

        sections.append("# Task: \(brief.title)")
        sections.append(brief.description.isEmpty ? "(no description)" : brief.description)

        if !brief.subtasks.isEmpty {
            var lines = ["## Subtasks"]
            for (index, subtask) in brief.subtasks.enumerated() {
                let mark = subtask.done ? "x" : " "
                lines.append("- [\(mark)] \(index + 1). \(subtask.title)")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        if !brief.shelf.isEmpty {
            var lines = ["## Files and folders"]
            for entry in brief.shelf {
                lines.append(entry.isDirectory ? "- \(entry.path) (folder)" : "- \(entry.path)")
            }
            sections.append(lines.joined(separator: "\n"))
        }

        if let deadline = brief.deadline {
            let seconds = deadline.timeIntervalSince(now)
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            let time = formatter.string(from: deadline)
            sections.append("## Time budget\nYou have \(minutes) minutes (until \(time)). Prioritize finishing within it.")
        }

        return sections.joined(separator: "\n\n")
    }

    static let bunnyToolsSentence = "You can read and manage the user's Bunny task list with the `bunny` tools (list_tasks, create_task, create_tasks, update_task, complete_task, add_to_shelf). Use them when the user asks you to add or organize tasks."

    /// `toolsAvailable`: the run has Bunny's MCP server attached, so mention the `bunny` tools.
    static func systemAppendix(for harness: AgentHarness, toolsAvailable: Bool = false) -> String {
        let askSentence: String
        switch harness {
        case .claudeCode:
            askSentence = "Claude: use the AskUserQuestion tool."
        case .codex:
            askSentence = "Codex: end your turn with exactly one <bunny-question>{\"question\": \"...\", \"options\": [\"...\", \"...\"]}</bunny-question> block (options optional; omit for free-text answers) and nothing after it. Only include a <bunny-question> block if you cannot continue without the user's decision. Never add one after finishing the task."
        }
        var bullets = [
            "You were handed this task from Bunny, a menu-bar task list. Work autonomously.",
            "Only ask the user when genuinely blocked or when a decision is theirs. \(askSentence)",
            "When you finish, reply with a short summary of what you did. If you completed specific subtasks, add a final line <bunny-subtasks-done>1,3</bunny-subtasks-done> with their numbers.",
        ]
        if toolsAvailable {
            bullets.append(bunnyToolsSentence)
        }
        return bullets.map { "- \($0)" }.joined(separator: "\n")
    }
}
