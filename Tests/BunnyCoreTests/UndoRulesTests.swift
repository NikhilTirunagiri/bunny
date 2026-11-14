import Testing
@testable import BunnyCore

struct UndoRulesTests {
    @Test func messages() {
        #expect(UndoRules.message(.trashed, count: 2) == "Moved 2 notes to Trash")
        #expect(UndoRules.message(.completed, count: 3) == "Completed 3 notes")
        #expect(UndoRules.message(.trashed, count: 1) == "Moved 1 note to Trash")
    }

    @Test func copiedNotice() {
        #expect(UndoRules.copiedMessage(count: 1) == "Copied 1 note")
        #expect(UndoRules.copiedMessage(count: 2) == "Copied 2 notes")
    }
}
