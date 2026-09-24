import Foundation
import os
import SwiftData

/// Runs Bunny tool calls (spec §5) against the SwiftData store on the main context, so agent-made
/// changes show up in the UI right away. Only one nesting level, like the rest of Bunny: a new
/// task's parent must be an existing top-level, non-archived task.
@MainActor
final class BunnyToolsBackendImpl: BunnyToolsBackend {
    private let modelContainer: ModelContainer
    private var context: ModelContext { modelContainer.mainContext }

    private static let log = Logger(subsystem: "bunny", category: "BunnyTools")

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func perform(_ call: BunnyToolCall, contextTaskID: UUID?) -> Result<String, BunnyToolError> {
        Self.log.info("tool call \(Self.name(of: call), privacy: .public) from task \(contextTaskID?.uuidString ?? "-", privacy: .public)")
        let result: Result<Any, BunnyToolError>
        switch call {
        case .listTasks(let includeCompleted):
            result = .success(listTasks(includeCompleted: includeCompleted))
        case .createTask(let newTask, let parentID):
            result = createTasks([newTask], parentID: parentID).map { created -> Any in created[0] }
        case .createTasks(let newTasks, let parentID):
            result = createTasks(newTasks, parentID: parentID).map { created -> Any in ["created": created] }
        case .updateTask(let id, let title, let description, let timerMinutes):
            result = updateTask(id, title: title, description: description, timerMinutes: timerMinutes)
        case .completeTask(let id, let completed):
            result = completeTask(id, completed: completed)
        case .addToShelf(let taskID, let paths):
            result = addToShelf(taskID, paths: paths)
        }
        return result.flatMap(Self.encode)
    }

    // MARK: - Tools

    private func listTasks(includeCompleted: Bool) -> [[String: Any]] {
        let active = activeTasks()
        let childrenByParent = Dictionary(grouping: active.filter { $0.parentID != nil }, by: { $0.parentID! })
        return active
            .filter { $0.parentID == nil && (includeCompleted || !$0.isCompleted) }
            .map { task in
                var json = summary(of: task)
                // Every live subtask, with its `completed` flag, so an agent can see what already exists.
                json["subtasks"] = (childrenByParent[task.id] ?? []).map { summary(of: $0) }
                return json
            }
    }

    /// Creates `newTasks` (each with its subtasks) at the end of the target sibling list.
    /// Validates everything first, so a failure creates nothing.
    private func createTasks(_ newTasks: [NewTask], parentID: UUID?) -> Result<[[String: Any]], BunnyToolError> {
        var parent: BunnyTask?
        if let parentID {
            guard let found = task(with: parentID), !found.isArchived else {
                return .failure(BunnyToolError(message: "No task with id \(parentID.uuidString)"))
            }
            guard found.parentID == nil else {
                return .failure(BunnyToolError(message: "Task \(parentID.uuidString) is a subtask; Bunny allows only one level of subtasks, so use a top-level task as parent_id"))
            }
            guard newTasks.allSatisfy({ $0.subtasks.isEmpty }) else {
                return .failure(BunnyToolError(message: "Subtasks can't have subtasks; omit subtasks when parent_id is set"))
            }
            parent = found
        }

        var nextOrder = nextSortOrder(parentID: parentID)
        var created: [[String: Any]] = []
        for newTask in newTasks {
            let task = BunnyTask(title: newTask.title, parentID: parentID, sortOrder: nextOrder)
            nextOrder += 1
            task.taskDescription = newTask.description ?? ""
            task.timerDuration = newTask.timerMinutes.map { $0 * 60 }
            context.insert(task)

            var subtaskIDs: [String] = []
            for (index, title) in newTask.subtasks.enumerated() {
                let subtask = BunnyTask(title: title, parentID: task.id, sortOrder: index)
                context.insert(subtask)
                subtaskIDs.append(subtask.id.uuidString)
            }
            created.append(["id": task.id.uuidString, "title": task.title, "subtask_ids": subtaskIDs])
        }
        parent?.isExpanded = true
        save()
        return .success(created)
    }

    private func updateTask(_ id: UUID, title: String?, description: String?,
                            timerMinutes: Double?) -> Result<Any, BunnyToolError> {
        liveTask(id).map { task -> Any in
            if let title { task.title = title }
            if let description { task.taskDescription = description }
            if let timerMinutes { task.timerDuration = timerMinutes * 60 }
            save()
            return summary(of: task)
        }
    }

    private func completeTask(_ id: UUID, completed: Bool) -> Result<Any, BunnyToolError> {
        liveTask(id).map { task -> Any in
            if task.isCompleted != completed {
                task.isCompleted = completed
                task.completedAt = completed ? Date() : nil
            }
            task.completedByAgent = false
            save()
            return summary(of: task)
        }
    }

    private func addToShelf(_ taskID: UUID, paths: [String]) -> Result<Any, BunnyToolError> {
        liveTask(taskID).map { task -> Any in
            let fileManager = FileManager.default
            var urls: [URL] = []
            var missing: [String] = []
            for path in paths {
                let expanded = (path as NSString).standardizingPath
                if fileManager.fileExists(atPath: expanded) {
                    urls.append(URL(fileURLWithPath: expanded))
                } else {
                    missing.append(path)
                }
            }
            let added = ShelfService.add(urls, to: task.id, in: context)
            save()
            return [
                "added": added,
                // Already on the shelf, or not bookmarkable.
                "skipped": urls.count - added,
                "missing": missing,
                "shelf": ShelfService.items(for: task.id, in: context).map(\.lastKnownPath),
            ] as [String: Any]
        }
    }

    // MARK: - Store

    /// Non-archived tasks in list order.
    private func activeTasks() -> [BunnyTask] {
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func task(with id: UUID) -> BunnyTask? {
        var descriptor = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// A non-archived task, or the "unknown id" tool error.
    private func liveTask(_ id: UUID) -> Result<BunnyTask, BunnyToolError> {
        guard let task = task(with: id), !task.isArchived else {
            return .failure(BunnyToolError(message: "No task with id \(id.uuidString)"))
        }
        return .success(task)
    }

    /// One past the largest `sortOrder` among the live siblings under `parentID` (nil = top level).
    private func nextSortOrder(parentID: UUID?) -> Int {
        let siblings = activeTasks().filter { $0.parentID == parentID }
        return (siblings.map(\.sortOrder).max() ?? -1) + 1
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Self.log.error("Bunny tools: save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - JSON

    private func summary(of task: BunnyTask) -> [String: Any] {
        [
            "id": task.id.uuidString,
            "title": task.title,
            "description": task.taskDescription,
            "completed": task.isCompleted,
            "parent_id": task.parentID?.uuidString ?? NSNull(),
            "timer_minutes": task.timerDuration.map { $0 / 60 } ?? NSNull(),
            "agent_state": task.agentState,
            "shelf": ShelfService.items(for: task.id, in: context).map(\.lastKnownPath),
        ]
    }

    private static func encode(_ value: Any) -> Result<String, BunnyToolError> {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return .failure(BunnyToolError(message: "Couldn't encode the result")) }
        return .success(text)
    }

    private static func name(of call: BunnyToolCall) -> String {
        switch call {
        case .listTasks: return "list_tasks"
        case .createTask: return "create_task"
        case .createTasks: return "create_tasks"
        case .updateTask: return "update_task"
        case .completeTask: return "complete_task"
        case .addToShelf: return "add_to_shelf"
        }
    }
}
