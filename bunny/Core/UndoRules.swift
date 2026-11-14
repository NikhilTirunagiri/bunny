import Foundation

/// The list actions that can be undone, and the Undo strip's wording.
enum UndoRules {
    enum Action: Equatable { case completed, trashed }

    /// "Completed 3 notes", "Moved 2 notes to Trash".
    static func message(_ action: Action, count: Int) -> String {
        let notes = count == 1 ? "1 note" : "\(count) notes"
        switch action {
        case .completed: return "Completed \(notes)"
        case .trashed: return "Moved \(notes) to Trash"
        }
    }

    /// "Copied 2 notes": the brief notice after Copy as Prompt (no Undo).
    static func copiedMessage(count: Int) -> String {
        count == 1 ? "Copied 1 note" : "Copied \(count) notes"
    }
}
