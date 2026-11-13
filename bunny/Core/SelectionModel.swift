import Foundation

/// Pure selection rules for a list of notes (click, ⌘-click, shift-click, arrows). The caller passes
/// the visible ids in display order; no model types.
enum SelectionModel {
    struct Selection: Equatable {
        var ids: Set<UUID> = []
        /// Where a shift-click range starts.
        var anchor: UUID?
        /// The last note clicked or moved to; arrows move from here, Return reopens it.
        var cursor: UUID?

        /// The one selected note, or nil when none or several are selected.
        var single: UUID? { ids.count == 1 ? ids.first : nil }
    }

    enum Input: Equatable {
        /// Plain click: select only this note; on the only selected note, deselect.
        case click(UUID)
        /// Select only this note (never deselects).
        case select(UUID)
        /// ⌘-click: add or remove one note.
        case toggle(UUID)
        /// Shift-click: select the range from the anchor to this note.
        case extend(UUID)
        case up, down
        case selectAll
        /// Notes that left the list (archived, trashed, deleted).
        case removed(Set<UUID>)
        case clear
    }

    static func apply(_ input: Input, to selection: Selection, visible: [UUID]) -> Selection {
        var s = selection
        switch input {
        case .click(let id):
            if s.ids == [id] {
                s.ids = []
            } else {
                s = only(id)
            }
        case .select(let id):
            s = only(id)
        case .toggle(let id):
            if s.ids.contains(id) { s.ids.remove(id) } else { s.ids.insert(id) }
            s.anchor = id
            s.cursor = id
        case .extend(let id):
            guard let anchor = s.anchor, let from = visible.firstIndex(of: anchor),
                  let to = visible.firstIndex(of: id) else { return only(id) }
            s.ids = Set(visible[min(from, to)...max(from, to)])
            s.cursor = id
        case .up, .down:
            guard !visible.isEmpty else { return Selection() }
            let next: Int
            if let cursor = s.cursor, let index = visible.firstIndex(of: cursor) {
                next = input == .up ? max(index - 1, 0) : min(index + 1, visible.count - 1)
            } else {
                next = input == .up ? visible.count - 1 : 0
            }
            s = only(visible[next])
        case .selectAll:
            s.ids = Set(visible)
            if s.anchor.map({ !visible.contains($0) }) ?? true { s.anchor = visible.first }
            if s.cursor.map({ !visible.contains($0) }) ?? true { s.cursor = visible.last }
        case .removed(let removed):
            s.ids.subtract(removed)
            if let anchor = s.anchor, removed.contains(anchor) { s.anchor = nil }
            if let cursor = s.cursor, removed.contains(cursor) { s.cursor = nil }
        case .clear:
            s.ids = []
        }
        return s
    }

    private static func only(_ id: UUID) -> Selection {
        Selection(ids: [id], anchor: id, cursor: id)
    }
}
