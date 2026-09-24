import Foundation
import SwiftData

/// Applies `TaskMoveRules` (spec §4) to the SwiftData store: renumbers the affected
/// sibling lists, expands a task's new parent and unpins tasks that become subtasks.
@MainActor
enum TaskMover {
    /// All non-archived tasks, in the same order the list shows them.
    private static func activeTasks(in context: ModelContext) -> [BunnyTask] {
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func nodes(for tasks: [BunnyTask]) -> [TaskNode] {
        tasks.map { TaskNode(id: $0.id, parentID: $0.parentID, sortOrder: $0.sortOrder) }
    }

    /// The zone a drop would actually use (into can degrade to below); nil = no-op.
    static func resolvedZone(dragged: UUID, target: UUID, zone: DropZone, in context: ModelContext) -> DropZone? {
        TaskMoveRules.resolve(dragged: dragged, target: target, zone: zone,
                              nodes: nodes(for: activeTasks(in: context)))
    }

    static func perform(dragged: UUID, target: UUID, zone: DropZone, in context: ModelContext) {
        let tasks = activeTasks(in: context)
        let placements = TaskMoveRules.move(dragged: dragged, target: target, zone: zone,
                                            nodes: nodes(for: tasks))
        guard !placements.isEmpty else { return }

        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for placement in placements {
            guard let task = byID[placement.id] else { continue }
            task.parentID = placement.parentID
            task.sortOrder = placement.sortOrder
        }

        guard let moved = byID[dragged], let newParentID = moved.parentID else { return }
        // Nesting: show the new subtask, and drop its pin (subtasks can't be pinned).
        byID[newParentID]?.isExpanded = true
        if moved.isPinned {
            moved.isPinned = false
        }
        let appState = AppState.shared
        if appState.pinnedTaskID == moved.id {
            appState.pinnedTaskID = nil
            appState.timerExpiredTaskID = nil
        }
    }
}
