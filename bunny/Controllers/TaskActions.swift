import Foundation
import SwiftData

/// Note lifecycle actions shared by rows, the bulk bar, the keyboard, the Archive/Trash view and the
/// scheduler: complete, archive, move to Trash, restore, delete forever. Each action on a top-level
/// note also applies to its subtasks, stops live agents, and keeps the selection and menu bar pin in sync.
@MainActor
enum TaskActions {
    // MARK: - Complete

    static func setCompleted(_ task: BunnyTask, _ completed: Bool) {
        guard task.isCompleted != completed else { return }
        task.isCompleted = completed
        task.completedAt = completed ? Date() : nil
        if !completed { task.completedByAgent = false }
    }

    /// Completes all of `ids`, or reopens them when all are already complete (Space).
    static func toggleComplete(_ ids: Set<UUID>, in context: ModelContext) {
        let targets = tasks(ids, in: context)
        let complete = targets.contains { !$0.isCompleted }
        for task in targets { setCompleted(task, complete) }
    }

    static func complete(_ ids: Set<UUID>, in context: ModelContext) {
        for task in tasks(ids, in: context) { setCompleted(task, true) }
    }

    // MARK: - Archive

    static func archive(_ ids: Set<UUID>, in context: ModelContext) {
        let now = Date()
        let family = withSubtasks(ids, in: context)
        for task in family {
            AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)
            task.archivedAt = now
            unpin(task)
        }
        PanelCoordinator.shared.tasksRemoved(family.map(\.id))
        try? context.save()
    }

    /// Back to the notes list, reopened, with no stale run state, question or session from before archiving.
    static func restoreFromArchive(_ ids: Set<UUID>, in context: ModelContext) {
        for task in withSubtasks(ids, in: context) where task.archivedAt != nil && task.deletedAt == nil {
            if task.runState.isActive { AgentSupervisor.shared.stop(task) }   // e.g. archived while needsInput
            AgentSupervisor.shared.clear(task)
            task.archivedAt = nil
            setCompleted(task, false)
            if task.isTimerExpired { task.timerStartedAt = nil }
        }
        try? context.save()
    }

    // MARK: - Trash

    static func moveToTrash(_ ids: Set<UUID>, in context: ModelContext) {
        let now = Date()
        let family = withSubtasks(ids, in: context).filter { $0.deletedAt == nil }
        for task in family {
            AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)
            task.deletedAt = now
            unpin(task)
        }
        PanelCoordinator.shared.tasksRemoved(family.map(\.id))
        try? context.save()
    }

    /// The note goes back where it was (notes list or Archive), with its subtasks.
    static func restoreFromTrash(_ ids: Set<UUID>, in context: ModelContext) {
        for task in withSubtasks(ids, in: context) { task.deletedAt = nil }
        try? context.save()
    }

    /// Deletes notes for good: the rows, their subtasks and their attachments, after stopping agents.
    /// Used by Delete Forever, Empty Trash and the automatic purge.
    static func deleteForever(_ ids: Set<UUID>, in context: ModelContext) {
        let family = withSubtasks(ids, in: context)
        for task in family {
            AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)
            ShelfService.removeAll(for: task.id, in: context)
            unpin(task)
        }
        PanelCoordinator.shared.tasksRemoved(family.map(\.id))
        for task in family { context.delete(task) }
        try? context.save()
    }

    // MARK: - Scheduled

    /// Purges notes whose Trash retention ran out (`trash.retentionDays`).
    static func purgeExpiredTrash(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []
        let records = all.map { TrashRules.Record(id: $0.id, parentID: $0.parentID, deletedAt: $0.deletedAt) }
        let ids = TrashRules.idsToPurge(records, retentionDays: NotesPreferences.trashRetentionDays, now: Date())
        if !ids.isEmpty { deleteForever(ids, in: context) }
    }

    /// Archives completed notes on the `notes.autoArchive` schedule (subtasks follow their parent).
    static func autoArchive(in context: ModelContext) {
        let policy = NotesPreferences.autoArchive
        guard policy != .never else { return }
        let now = Date()
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.isCompleted && $0.archivedAt == nil && $0.deletedAt == nil })
        let due = ((try? context.fetch(descriptor)) ?? []).filter { task in
            // Notes completed before `completedAt` was recorded count as due.
            guard let completedAt = task.completedAt else { return true }
            return TrashRules.isDueForArchive(completedAt: completedAt, policy: policy, now: now, calendar: .current)
        }
        if !due.isEmpty { archive(Set(due.map(\.id)), in: context) }
    }

    // MARK: - Helpers

    private static func tasks(_ ids: Set<UUID>, in context: ModelContext) -> [BunnyTask] {
        guard !ids.isEmpty else { return [] }
        return ((try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []).filter { ids.contains($0.id) }
    }

    /// `ids` plus every subtask of them (one nesting level, as everywhere in Bunny).
    private static func withSubtasks(_ ids: Set<UUID>, in context: ModelContext) -> [BunnyTask] {
        guard !ids.isEmpty else { return [] }
        let all = (try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []
        return all.filter { ids.contains($0.id) || $0.parentID.map(ids.contains) == true }
    }

    private static func unpin(_ task: BunnyTask) {
        let appState = AppState.shared
        if task.isPinned { task.isPinned = false }
        if appState.pinnedTaskID == task.id {
            appState.pinnedTaskID = nil
            appState.timerExpiredTaskID = nil
        }
    }
}
