import Foundation
import Testing
@testable import BunnyCore

struct NotePromptTests {
    @Test func titleOnly() {
        #expect(NotePrompt.text(for: [NotePrompt.Note(title: "Buy milk")]) == "Buy milk")
    }

    @Test func allParts() {
        let note = NotePrompt.Note(
            title: "Fix login",
            details: "Users get logged out.",
            subtasks: [("Repro", false), ("Patch", true)],
            attachments: ["/Users/n/code/app", "/Users/n/notes.md"])
        let expected = """
        Fix login

        Users get logged out.

        - [ ] Repro
        - [x] Patch

        Attachments:
        /Users/n/code/app
        /Users/n/notes.md
        """
        #expect(NotePrompt.text(for: [note]) == expected)
    }

    @Test func severalNotesAreSeparatedByARule() {
        let notes = [NotePrompt.Note(title: "One", details: "First."), NotePrompt.Note(title: "Two")]
        #expect(NotePrompt.text(for: notes) == "One\n\nFirst.\n\n---\n\nTwo")
    }

    @Test func noNotesGiveAnEmptyString() {
        #expect(NotePrompt.text(for: []) == "")
    }
}
