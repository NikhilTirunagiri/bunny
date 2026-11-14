import Foundation

/// "Copy as Prompt": notes as plain text to paste into any agent or chat. Not the hand-off prompt
/// (`AgentPromptBuilder`), which adds headings, numbering and a time budget for Bunny's own runs.
enum NotePrompt {
    struct Note: Equatable {
        var title: String
        var details: String = ""
        var subtasks: [(title: String, done: Bool)] = []
        /// Absolute paths.
        var attachments: [String] = []

        static func == (a: Note, b: Note) -> Bool {
            a.title == b.title && a.details == b.details && a.attachments == b.attachments
                && a.subtasks.elementsEqual(b.subtasks, by: ==)
        }
    }

    /// Title, details, subtasks as a checklist, attachment paths; empty parts are left out. Several
    /// notes are separated by a blank line and a rule.
    static func text(for notes: [Note]) -> String {
        notes.map { note in
            var parts = [note.title]
            if !note.details.isEmpty { parts.append(note.details) }
            if !note.subtasks.isEmpty {
                parts.append(note.subtasks.map { "- [\($0.done ? "x" : " ")] \($0.title)" }.joined(separator: "\n"))
            }
            if !note.attachments.isEmpty {
                parts.append((["Attachments:"] + note.attachments).joined(separator: "\n"))
            }
            return parts.joined(separator: "\n\n")
        }
        .joined(separator: "\n\n---\n\n")
    }
}
