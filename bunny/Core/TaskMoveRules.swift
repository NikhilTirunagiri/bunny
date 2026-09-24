import CoreGraphics
import Foundation

/// A task's position in the tree: which parent it belongs to (nil = top-level) and its
/// order among siblings.
struct TaskNode: Equatable {
    let id: UUID
    var parentID: UUID?
    var sortOrder: Int
    /// False when this task must not move under a (new) parent: it has subtasks (incl.
    /// archived ones), a timer, or an agent run or session. It can still move to the top
    /// level or reorder within its current parent. The rules also refuse nesting a task that
    /// has subtasks among `nodes`, whatever this flag says.
    var canNest: Bool = true
}

/// Where a drop landed within a row.
enum DropZone: Equatable {
    case above, below, into
}

/// A task's new parent/order after a move.
struct TaskPlacement: Equatable {
    let id: UUID
    let parentID: UUID?
    let sortOrder: Int
}

/// Pure rules for drag-to-reorder and drag-into-nest (see spec §4). No SwiftData, no UI.
enum TaskMoveRules {
    /// Zone from pointer y within a row of height h: y < 0.3h → above, y > 0.7h → below, else into.
    /// On an expanded parent whose subtasks sit right beneath it, the bottom zone means "into"
    /// (append as its last subtask) rather than "below" (after the whole subtask block).
    static func zone(y: CGFloat, height: CGFloat, expandedWithChildren: Bool = false) -> DropZone {
        if y < 0.3 * height { return .above }
        if y > 0.7 * height { return expandedWithChildren ? .into : .below }
        return .into
    }

    /// Effective zone after rules (into → below when not allowed). nil = no-op.
    static func resolve(dragged: UUID, target: UUID, zone: DropZone, nodes: [TaskNode]) -> DropZone? {
        guard dragged != target else { return nil }
        guard let draggedNode = nodes.first(where: { $0.id == dragged }),
              let targetNode = nodes.first(where: { $0.id == target }) else { return nil }
        // Only one nesting level: dropping a task onto its own subtask is a no-op.
        if targetNode.parentID == dragged { return nil }

        let draggedCanNest = draggedNode.canNest && !nodes.contains { $0.parentID == dragged }
        let targetIsTopLevel = targetNode.parentID == nil

        // Only one nesting level, and agent/timer tasks stay top-level: a task that can't
        // nest may only land at the top level, or reorder within its current parent.
        if !draggedCanNest {
            // Into a subtask means below it (one nesting level), as for any task.
            let effectiveZone: DropZone = (zone == .into && !targetIsTopLevel) ? .below : zone
            let destinationParent = effectiveZone == .into ? target : targetNode.parentID
            if destinationParent == nil || destinationParent == draggedNode.parentID {
                return effectiveZone
            }
            // Into another top-level task degrades to below it, which keeps the task top-level.
            return effectiveZone == .into ? .below : nil
        }

        switch zone {
        case .above, .below:
            return zone
        case .into:
            return targetIsTopLevel ? .into : .below
        }
    }

    /// New placements for every task whose parentID/sortOrder changes (source & destination
    /// sibling lists renumbered 0…n, ordered by current sortOrder then input order).
    static func move(dragged: UUID, target: UUID, zone: DropZone, nodes: [TaskNode]) -> [TaskPlacement] {
        guard let effectiveZone = resolve(dragged: dragged, target: target, zone: zone, nodes: nodes) else {
            return []
        }
        guard let draggedNode = nodes.first(where: { $0.id == dragged }),
              let targetNode = nodes.first(where: { $0.id == target }) else {
            return []
        }

        let newParentID: UUID?
        switch effectiveZone {
        case .into:
            newParentID = target
        case .above, .below:
            newParentID = targetNode.parentID
        }
        let oldParentID = draggedNode.parentID

        let indexByID = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($0.element.id, $0.offset) })
        func siblings(of parentID: UUID?, excluding excludedID: UUID) -> [TaskNode] {
            nodes.filter { $0.parentID == parentID && $0.id != excludedID }
                .sorted { a, b in
                    if a.sortOrder != b.sortOrder { return a.sortOrder < b.sortOrder }
                    return (indexByID[a.id] ?? 0) < (indexByID[b.id] ?? 0)
                }
        }

        var destSiblings = siblings(of: newParentID, excluding: dragged)
        switch effectiveZone {
        case .into:
            destSiblings.append(draggedNode)
        case .above:
            if let idx = destSiblings.firstIndex(where: { $0.id == target }) {
                destSiblings.insert(draggedNode, at: idx)
            } else {
                destSiblings.append(draggedNode)
            }
        case .below:
            if let idx = destSiblings.firstIndex(where: { $0.id == target }) {
                destSiblings.insert(draggedNode, at: idx + 1)
            } else {
                destSiblings.append(draggedNode)
            }
        }

        var placements: [TaskPlacement] = []
        for (i, node) in destSiblings.enumerated() {
            if node.parentID != newParentID || node.sortOrder != i {
                placements.append(TaskPlacement(id: node.id, parentID: newParentID, sortOrder: i))
            }
        }

        if oldParentID != newParentID {
            let sourceSiblings = siblings(of: oldParentID, excluding: dragged)
            for (i, node) in sourceSiblings.enumerated() where node.sortOrder != i {
                placements.append(TaskPlacement(id: node.id, parentID: oldParentID, sortOrder: i))
            }
        }

        return placements
    }
}
