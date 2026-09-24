import Foundation
import Testing
@testable import BunnyCore

struct BunnyToolArgumentsTests {

    // MARK: - list_tasks

    @Test func listTasksDefaultsIncludeCompletedFalse() {
        let result = BunnyToolArguments.parse(name: "list_tasks", arguments: [:])
        #expect(result == .success(.listTasks(includeCompleted: false)))
    }

    @Test func listTasksHonorsIncludeCompletedTrue() {
        let result = BunnyToolArguments.parse(name: "list_tasks", arguments: ["include_completed": true])
        #expect(result == .success(.listTasks(includeCompleted: true)))
    }

    @Test func listTasksRejectsWrongType() {
        let result = BunnyToolArguments.parse(name: "list_tasks", arguments: ["include_completed": "yes"])
        #expect(isFailure(result))
    }

    // MARK: - create_task

    @Test func createTaskMinimalValid() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "Buy milk"])
        let expected = NewTask(title: "Buy milk", description: nil, timerMinutes: nil, subtasks: [])
        #expect(result == .success(.createTask(expected, parentID: nil)))
    }

    @Test func createTaskTrimsTitle() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "  Buy milk  "])
        let expected = NewTask(title: "Buy milk", description: nil, timerMinutes: nil, subtasks: [])
        #expect(result == .success(.createTask(expected, parentID: nil)))
    }

    @Test func createTaskMissingTitleFails() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: [:])
        #expect(isFailure(result))
    }

    @Test func createTaskEmptyTitleFails() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "   "])
        #expect(isFailure(result))
    }

    @Test func createTaskWrongTypeTitleFailsWithTypeMessage() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": 123])
        #expect(result == .failure(BunnyToolError(message: "title must be a string")))
    }

    @Test func createTaskMissingTitleFailsWithRequiredMessage() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: [:])
        #expect(result == .failure(BunnyToolError(message: "title is required")))
    }

    @Test func createTaskTitleOverCapFails() {
        let longTitle = String(repeating: "a", count: 201)
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": longTitle])
        #expect(isFailure(result))
    }

    @Test func createTaskTitleAtCapSucceeds() {
        let title = String(repeating: "a", count: 200)
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": title])
        #expect(isSuccess(result))
    }

    @Test func createTaskDescriptionOverCapFails() {
        let longDescription = String(repeating: "a", count: 10_001)
        let result = BunnyToolArguments.parse(
            name: "create_task",
            arguments: ["title": "T", "description": longDescription]
        )
        #expect(isFailure(result))
    }

    @Test func createTaskDescriptionAtCapSucceeds() {
        let description = String(repeating: "a", count: 10_000)
        let result = BunnyToolArguments.parse(
            name: "create_task",
            arguments: ["title": "T", "description": description]
        )
        #expect(isSuccess(result))
    }

    @Test func createTaskValidTimerMinutes() {
        let result = BunnyToolArguments.parse(
            name: "create_task",
            arguments: ["title": "T", "timer_minutes": 25]
        )
        let expected = NewTask(title: "T", description: nil, timerMinutes: 25, subtasks: [])
        #expect(result == .success(.createTask(expected, parentID: nil)))
    }

    @Test func createTaskTimerMinutesZeroFails() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "timer_minutes": 0])
        #expect(isFailure(result))
    }

    @Test func createTaskTimerMinutesNegativeFails() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "timer_minutes": -5])
        #expect(isFailure(result))
    }

    @Test func createTaskTimerMinutesOverCapFails() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "timer_minutes": 1441])
        #expect(isFailure(result))
    }

    @Test func createTaskTimerMinutesAtCapSucceeds() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "timer_minutes": 1440])
        #expect(isSuccess(result))
    }

    @Test func createTaskWithSubtasks() {
        let result = BunnyToolArguments.parse(
            name: "create_task",
            arguments: ["title": "T", "subtasks": ["Sub 1", " Sub 2 "]]
        )
        let expected = NewTask(title: "T", description: nil, timerMinutes: nil, subtasks: ["Sub 1", "Sub 2"])
        #expect(result == .success(.createTask(expected, parentID: nil)))
    }

    @Test func createTaskSubtaskEmptyTitleFails() {
        let result = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "subtasks": ["   "]])
        #expect(isFailure(result))
    }

    @Test func createTaskWithValidParentID() {
        let id = UUID()
        let result = BunnyToolArguments.parse(
            name: "create_task",
            arguments: ["title": "T", "parent_id": id.uuidString]
        )
        let expected = NewTask(title: "T", description: nil, timerMinutes: nil, subtasks: [])
        #expect(result == .success(.createTask(expected, parentID: id)))
    }

    @Test func createTaskWithInvalidParentIDFails() {
        let result = BunnyToolArguments.parse(
            name: "create_task",
            arguments: ["title": "T", "parent_id": "not-a-uuid"]
        )
        #expect(isFailure(result))
    }

    // MARK: - create_tasks

    @Test func createTasksValidBatch() {
        let result = BunnyToolArguments.parse(
            name: "create_tasks",
            arguments: ["tasks": [["title": "A"], ["title": "B"]]]
        )
        let expected: [NewTask] = [
            NewTask(title: "A", description: nil, timerMinutes: nil, subtasks: []),
            NewTask(title: "B", description: nil, timerMinutes: nil, subtasks: []),
        ]
        #expect(result == .success(.createTasks(expected, parentID: nil)))
    }

    @Test func createTasksWithParentID() {
        let id = UUID()
        let result = BunnyToolArguments.parse(
            name: "create_tasks",
            arguments: ["tasks": [["title": "A"]], "parent_id": id.uuidString]
        )
        let expected: [NewTask] = [NewTask(title: "A", description: nil, timerMinutes: nil, subtasks: [])]
        #expect(result == .success(.createTasks(expected, parentID: id)))
    }

    @Test func createTasksMissingTasksFails() {
        let result = BunnyToolArguments.parse(name: "create_tasks", arguments: [:])
        #expect(isFailure(result))
    }

    @Test func createTasksOverBatchCapFails() {
        let tasks = (0..<101).map { ["title": "T\($0)"] }
        let result = BunnyToolArguments.parse(name: "create_tasks", arguments: ["tasks": tasks])
        #expect(isFailure(result))
    }

    @Test func createTasksAtBatchCapSucceeds() {
        let tasks = (0..<100).map { ["title": "T\($0)"] }
        let result = BunnyToolArguments.parse(name: "create_tasks", arguments: ["tasks": tasks])
        #expect(isSuccess(result))
    }

    @Test func createTasksInvalidEntryFails() {
        let result = BunnyToolArguments.parse(
            name: "create_tasks",
            arguments: ["tasks": [["title": "A"], ["title": ""]]]
        )
        #expect(isFailure(result))
    }

    // MARK: - update_task

    @Test func updateTaskIDOnly() {
        let id = UUID()
        let result = BunnyToolArguments.parse(name: "update_task", arguments: ["id": id.uuidString])
        #expect(result == .success(.updateTask(id: id, title: nil, description: nil, timer: nil)))
    }

    @Test func updateTaskAllFields() {
        let id = UUID()
        let result = BunnyToolArguments.parse(
            name: "update_task",
            arguments: ["id": id.uuidString, "title": "New", "description": "Desc", "timer_minutes": 10]
        )
        #expect(result == .success(.updateTask(id: id, title: "New", description: "Desc", timer: .set(minutes: 10))))
    }

    @Test func updateTaskMissingIDFails() {
        let result = BunnyToolArguments.parse(name: "update_task", arguments: [:])
        #expect(isFailure(result))
    }

    @Test func updateTaskInvalidIDFails() {
        let result = BunnyToolArguments.parse(name: "update_task", arguments: ["id": "nope"])
        #expect(isFailure(result))
    }

    @Test func updateTaskEmptyTitleFails() {
        let result = BunnyToolArguments.parse(
            name: "update_task",
            arguments: ["id": UUID().uuidString, "title": "   "]
        )
        #expect(isFailure(result))
    }

    @Test func updateTaskInvalidTimerFails() {
        let result = BunnyToolArguments.parse(
            name: "update_task",
            arguments: ["id": UUID().uuidString, "timer_minutes": 2000]
        )
        #expect(isFailure(result))
    }

    @Test func updateTaskTimerZeroOrNullClears() {
        let id = UUID()
        for value: Any in [0, 0.0, NSNull()] {
            let result = BunnyToolArguments.parse(name: "update_task", arguments: ["id": id.uuidString, "timer_minutes": value])
            #expect(result == .success(.updateTask(id: id, title: nil, description: nil, timer: .clear)))
        }
    }

    @Test func updateTaskNegativeTimerFails() {
        let result = BunnyToolArguments.parse(name: "update_task", arguments: ["id": UUID().uuidString, "timer_minutes": -1])
        #expect(isFailure(result))
    }

    // MARK: - Booleans are not numbers

    @Test func booleanTimerIsRejected() {
        for value: Any in [true, false, NSNumber(value: true)] {
            #expect(isFailure(BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "timer_minutes": value])))
            #expect(isFailure(BunnyToolArguments.parse(name: "update_task", arguments: ["id": UUID().uuidString, "timer_minutes": value])))
        }
    }

    @Test func jsonBooleanTimerIsRejected() throws {
        let json = #"{"title": "T", "timer_minutes": true}"#
        let arguments = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(isFailure(BunnyToolArguments.parse(name: "create_task", arguments: arguments)))

        let numeric = #"{"title": "T", "timer_minutes": 1}"#
        let numericArguments = try #require(try JSONSerialization.jsonObject(with: Data(numeric.utf8)) as? [String: Any])
        let expected = NewTask(title: "T", description: nil, timerMinutes: 1, subtasks: [])
        #expect(BunnyToolArguments.parse(name: "create_task", arguments: numericArguments) == .success(.createTask(expected, parentID: nil)))
    }

    // MARK: - Subtask limits

    @Test func subtasksCappedAtFifty() {
        let fifty = (1...50).map { "S\($0)" }
        let ok = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "subtasks": fifty])
        #expect(ok == .success(.createTask(NewTask(title: "T", description: nil, timerMinutes: nil, subtasks: fifty), parentID: nil)))
        let tooMany = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "subtasks": fifty + ["S51"]])
        #expect(isFailure(tooMany))
        let batch = BunnyToolArguments.parse(name: "create_tasks", arguments: ["tasks": [["title": "T", "subtasks": fifty + ["S51"]]]])
        #expect(isFailure(batch))
    }

    @Test func subtaskTimerIsRejected() {
        let parent = UUID().uuidString
        let single = BunnyToolArguments.parse(name: "create_task", arguments: ["title": "T", "parent_id": parent, "timer_minutes": 5])
        #expect(single == .failure(BunnyToolArguments.subtaskTimerError))
        let batch = BunnyToolArguments.parse(
            name: "create_tasks",
            arguments: ["parent_id": parent, "tasks": [["title": "A"], ["title": "B", "timer_minutes": 5]]]
        )
        #expect(batch == .failure(BunnyToolArguments.subtaskTimerError))
        // Without parent_id a timer is fine.
        let topLevel = BunnyToolArguments.parse(name: "create_tasks", arguments: ["tasks": [["title": "B", "timer_minutes": 5]]])
        #expect(!isFailure(topLevel))
    }

    // MARK: - complete_task

    @Test func completeTaskDefaultsToTrue() {
        let id = UUID()
        let result = BunnyToolArguments.parse(name: "complete_task", arguments: ["id": id.uuidString])
        #expect(result == .success(.completeTask(id: id, completed: true)))
    }

    @Test func completeTaskExplicitFalse() {
        let id = UUID()
        let result = BunnyToolArguments.parse(
            name: "complete_task",
            arguments: ["id": id.uuidString, "completed": false]
        )
        #expect(result == .success(.completeTask(id: id, completed: false)))
    }

    @Test func completeTaskInvalidIDFails() {
        let result = BunnyToolArguments.parse(name: "complete_task", arguments: ["id": "nope"])
        #expect(isFailure(result))
    }

    // MARK: - add_to_shelf

    @Test func addToShelfValid() {
        let id = UUID()
        let result = BunnyToolArguments.parse(
            name: "add_to_shelf",
            arguments: ["task_id": id.uuidString, "paths": ["/Users/n/a.txt", "/Users/n/b.txt"]]
        )
        #expect(result == .success(.addToShelf(taskID: id, paths: ["/Users/n/a.txt", "/Users/n/b.txt"])))
    }

    @Test func addToShelfRelativePathFails() {
        let result = BunnyToolArguments.parse(
            name: "add_to_shelf",
            arguments: ["task_id": UUID().uuidString, "paths": ["relative/path.txt"]]
        )
        #expect(isFailure(result))
    }

    @Test func addToShelfMissingPathsFails() {
        let result = BunnyToolArguments.parse(name: "add_to_shelf", arguments: ["task_id": UUID().uuidString])
        #expect(isFailure(result))
    }

    @Test func addToShelfEmptyPathsFails() {
        let result = BunnyToolArguments.parse(
            name: "add_to_shelf",
            arguments: ["task_id": UUID().uuidString, "paths": []]
        )
        #expect(isFailure(result))
    }

    @Test func addToShelfInvalidTaskIDFails() {
        let result = BunnyToolArguments.parse(name: "add_to_shelf", arguments: ["task_id": "nope", "paths": ["/a"]])
        #expect(isFailure(result))
    }

    // MARK: - unknown tool

    @Test func unknownToolNameFails() {
        let result = BunnyToolArguments.parse(name: "nonexistent_tool", arguments: [:])
        #expect(isFailure(result))
    }
}

private func isSuccess(_ result: Result<BunnyToolCall, BunnyToolError>) -> Bool {
    if case .success = result { return true }
    return false
}

private func isFailure(_ result: Result<BunnyToolCall, BunnyToolError>) -> Bool {
    if case .failure = result { return true }
    return false
}
