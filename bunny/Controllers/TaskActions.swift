import AppKit
import SwiftData

/// Note lifecycle actions shared by rows, the action strip, the keyboard, the Trash view and the
/// scheduler: complete, move to Trash, restore, delete forever. Each action on a top-level
/// note also applies to its subtasks, stops live agents, and keeps the selection and menu bar pin in sync.
/// `undoable`: the action came from the notes list, so the action strip offers Undo for it.
@MainActor
enum TaskActions {
    // MARK: - Complete

    static func setCompleted(_ task: BunnyTask, _ completed: Bool) {
        guard task.isCompleted != completed else { return }
        task.isCompleted = completed
        task.completedAt = completed ? Date() : nil
        if !completed { task.completedByAgent = false }
    }

    /// Completes all of `ids`, or reopens them when all are already complete (Space, the checkbox).
    static func toggleComplete(_ ids: Set<UUID>, in context: ModelContext, undoable: Bool = false) {
        let targets = tasks(ids, in: context)
        if targets.contains(where: { !$0.isCompleted }) {
            complete(ids, in: context, undoable: undoable)
        } else {
            for task in targets { setCompleted(task, false) }
        }
    }

    static func complete(_ ids: Set<UUID>, in context: ModelContext, undoable: Bool = false) {
        let targets = tasks(ids, in: context).filter { !$0.isCompleted }
        guard !targets.isEmpty else { return }
        let undo = undoable ? undoOffer(.completed, count: targets.count, for: targets, in: context) : nil
        for task in targets { setCompleted(task, true) }
        // A multi-selection's actions would take the Undo offer's place in the action strip.
        if undoable && PanelCoordinator.shared.selection.ids.count > 1 { PanelCoordinator.shared.apply(.clear) }
        undo?()
    }

    // MARK: - Trash

    static func moveToTrash(_ ids: Set<UUID>, in context: ModelContext, undoable: Bool = false) {
        let now = Date()
        let family = withSubtasks(ids, in: context).filter { $0.deletedAt == nil }
        guard !family.isEmpty else { return }
        let undo = undoable ? undoOffer(.trashed, count: family.filter { ids.contains($0.id) }.count,
                                        for: family, in: context) : nil
        for task in family {
            AgentSupervisor.shared.taskWillBeDeleted(task.id)
            task.deletedAt = now
            unpin(task)
        }
        PanelCoordinator.shared.tasksRemoved(family.map(\.id))
        try? context.save()
        undo?()
    }

    /// The note goes back to the notes list as it was, open or completed, with its subtasks. A
    /// completed note's retention starts again, or the next housekeeping would trash it straight away.
    static func restoreFromTrash(_ ids: Set<UUID>, in context: ModelContext) {
        let now = Date()
        for task in withSubtasks(ids, in: context) where task.deletedAt != nil {
            task.deletedAt = nil
            if task.isCompleted { task.completedAt = now }
        }
        try? context.save()
    }

    /// Delete Forever / Empty Trash: asks first (in-window, `DeleteConfirmationView`) unless "Do not
    /// ask again" was chosen (`trash.confirmDeleteForever`).
    static func confirmDeleteForever(_ ids: Set<UUID>, emptying: Bool = false, in context: ModelContext) {
        guard !ids.isEmpty else { return }
        let delete = { deleteForever(ids, in: context) }
        guard NotesPreferences.confirmDeleteForever else {
            delete()
            return
        }
        PanelCoordinator.shared.deleteConfirmation = DeleteConfirmation(
            title: emptying ? "Empty Trash?" : "Delete forever?",
            confirmTitle: emptying ? "Empty Trash" : "Delete Forever",
            onConfirm: delete)
    }

    /// Deletes notes for good: the rows, their subtasks and their attachments (with the files Bunny
    /// stored for them, `ShelfService.removeAll`), after stopping agents.
    /// Used by Delete Forever, Empty Trash and the automatic purge.
    static func deleteForever(_ ids: Set<UUID>, in context: ModelContext) {
        let family = withSubtasks(ids, in: context)
        for task in family {
            AgentSupervisor.shared.taskWillBeDeleted(task.id)
            ShelfService.removeAll(for: task.id, in: context)
            unpin(task)
        }
        PanelCoordinator.shared.tasksRemoved(family.map(\.id))
        for task in family { context.delete(task) }
        try? context.save()
    }

    // MARK: - Undo

    /// Records where `tasks` stand now (call before changing them) and returns the call that puts the
    /// Undo strip up once the change is made. Undo sets each note back exactly: completion,
    /// Trash, and the menu bar pin if the action cleared it. An agent the action stopped stays stopped.
    private static func undoOffer(_ action: UndoRules.Action, count: Int, for tasks: [BunnyTask],
                                  in context: ModelContext) -> () -> Void {
        struct Before {
            let id: UUID, isCompleted: Bool, completedAt: Date?, completedByAgent: Bool
            let deletedAt: Date?, isPinned: Bool
        }
        let before = tasks.map {
            Before(id: $0.id, isCompleted: $0.isCompleted, completedAt: $0.completedAt,
                   completedByAgent: $0.completedByAgent,
                   deletedAt: $0.deletedAt, isPinned: $0.isPinned)
        }
        return {
            PanelCoordinator.shared.offerUndo(UndoRules.message(action, count: count)) {
                let all = (try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []
                let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                for state in before {
                    guard let task = byID[state.id] else { continue }
                    task.isCompleted = state.isCompleted
                    task.completedAt = state.completedAt
                    task.completedByAgent = state.completedByAgent
                    task.deletedAt = state.deletedAt
                    // The pin comes back unless another note took the menu bar meanwhile.
                    if state.isPinned && !task.isPinned && AppState.shared.pinnedTaskID == nil {
                        task.isPinned = true
                        AppState.shared.pinnedTaskID = task.id
                    }
                }
                try? context.save()
            }
        }
    }

    // MARK: - Copy as Prompt

    /// Puts the notes on the clipboard as plain text (`NotePrompt`), in list order. A subtask whose
    /// parent is also copied is left out: it is already in the parent's checklist.
    static func copyAsPrompt(_ ids: Set<UUID>, in context: ModelContext) {
        let descriptor = FetchDescriptor<BunnyTask>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        let live = ((try? context.fetch(descriptor)) ?? []).filter(\.isLive)
        let notes = live.filter { ids.contains($0.id) && !($0.parentID.map(ids.contains) ?? false) }.map { task in
            NotePrompt.Note(
                title: task.title,
                details: task.taskDescription,
                subtasks: live.filter { $0.parentID == task.id }.map { ($0.title, $0.isCompleted) },
                attachments: ShelfService.items(for: task.id, in: context).map(\.lastKnownPath))
        }
        guard !notes.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(NotePrompt.text(for: notes), forType: .string)
        PanelCoordinator.shared.showNotice(UndoRules.copiedMessage(count: notes.count))
    }

    // MARK: - Scheduled

    /// Purges notes whose Trash retention ran out (`trash.retentionDays`).
    static func purgeExpiredTrash(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []
        let records = all.map { TrashRules.Record(id: $0.id, parentID: $0.parentID, deletedAt: $0.deletedAt) }
        let ids = TrashRules.idsToPurge(records, retentionDays: NotesPreferences.trashRetentionDays, now: Date())
        if !ids.isEmpty { deleteForever(ids, in: context) }
    }

    /// Moves completed notes to Trash once `notes.completedRetention` has run out (subtasks follow
    /// their parent), like a manual delete but with no Undo offer.
    static func trashExpiredCompleted(in context: ModelContext) {
        let retention = NotesPreferences.completedRetention
        guard retention != .never else { return }
        let now = Date()
        // Top-level notes only (the Completed group): a done subtask stays with its open parent.
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.isCompleted && $0.parentID == nil && $0.deletedAt == nil })
        let due = ((try? context.fetch(descriptor)) ?? []).filter { task in
            // Notes completed before `completedAt` was recorded count as due.
            guard let completedAt = task.completedAt else { return true }
            return TrashRules.isDueForTrash(completedAt: completedAt, retention: retention, now: now)
        }
        if !due.isEmpty { moveToTrash(Set(due.map(\.id)), in: context) }
    }

    /// Once at launch: notes archived by older versions (the Archive is gone) move to Trash, with the
    /// full Trash retention ahead of them. `archivedAt` is emptied and never read again.
    static func migrateArchived(in context: ModelContext) {
        let descriptor = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.archivedAt != nil })
        guard let archived = try? context.fetch(descriptor), !archived.isEmpty else { return }
        let now = Date()
        for task in archived {
            if task.deletedAt == nil { task.deletedAt = now }
            task.archivedAt = nil
        }
        try? context.save()
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

    /// Shows `task` in the menu bar, in place of the note shown there before.
    static func pin(_ task: BunnyTask) {
        let pinned = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.isPinned })
        for other in (try? task.modelContext?.fetch(pinned)) ?? [] { other.isPinned = false }
        task.isPinned = true
        AppState.shared.pinnedTaskID = task.id
    }

    static func unpin(_ task: BunnyTask) {
        let appState = AppState.shared
        if task.isPinned { task.isPinned = false }
        if appState.pinnedTaskID == task.id {
            appState.pinnedTaskID = nil
        }
    }
}
