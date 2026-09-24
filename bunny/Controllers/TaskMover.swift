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

    /// Tree nodes for the active tasks. A task can't nest when it has subtasks — counted over
    /// all tasks, archived included, so restoring them can't create grandchildren — or when it
    /// has a timer or any agent state (a run, or a finished session: subtasks have no agent
    /// button, so nesting would hide the session).
    private static func nodes(for tasks: [BunnyTask], in context: ModelContext) -> [TaskNode] {
        let allParentIDs = Set(((try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []).compactMap(\.parentID))
        return tasks.map { task in
            TaskNode(id: task.id, parentID: task.parentID, sortOrder: task.sortOrder,
                     canNest: !allParentIDs.contains(task.id) && !task.hasTimer
                        && task.runState == .idle && task.agentSessionID == nil)
        }
    }

    /// The zone a drop would actually use (into can degrade to below); nil = no-op.
    static func resolvedZone(dragged: UUID, target: UUID, zone: DropZone, in context: ModelContext) -> DropZone? {
        TaskMoveRules.resolve(dragged: dragged, target: target, zone: zone,
                              nodes: nodes(for: activeTasks(in: context), in: context))
    }

    static func perform(dragged: UUID, target: UUID, zone: DropZone, in context: ModelContext) {
        let tasks = activeTasks(in: context)
        let placements = TaskMoveRules.move(dragged: dragged, target: target, zone: zone,
                                            nodes: nodes(for: tasks, in: context))
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
