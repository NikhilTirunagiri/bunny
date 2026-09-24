import Foundation

/// Parses and validates `tools/call` arguments (a `[String: Any]` decoded from JSON, or built
/// directly in tests) into a `BunnyToolCall`.
///
/// Validation rules (shared across tools):
/// - Titles are trimmed, must be non-empty, and capped at 200 characters.
/// - Descriptions are capped at 10,000 characters.
/// - `timer_minutes` must be greater than 0 and at most 1440.
/// - Batches (`create_tasks`) hold at most 100 tasks.
/// - UUIDs are parsed strictly.
/// - `paths` must be absolute.
enum BunnyToolArguments {
    static func parse(name: String, arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        switch name {
        case "list_tasks":
            return parseListTasks(arguments)
        case "create_task":
            return parseCreateTask(arguments)
        case "create_tasks":
            return parseCreateTasks(arguments)
        case "update_task":
            return parseUpdateTask(arguments)
        case "complete_task":
            return parseCompleteTask(arguments)
        case "add_to_shelf":
            return parseAddToShelf(arguments)
        default:
            return .failure(BunnyToolError(message: "Unknown tool: \(name)"))
        }
    }

    // MARK: - Tools

    private static func parseListTasks(_ arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        validatedBool(arguments, key: "include_completed", default: false)
            .map { .listTasks(includeCompleted: $0) }
    }

    private static func parseCreateTask(_ arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        validatedTitle(arguments["title"]).flatMap { title in
            validatedDescription(arguments).flatMap { description in
                validatedTimerMinutes(arguments).flatMap { timer in
                    validatedSubtasks(arguments).flatMap { subtasks in
                        validatedOptionalUUID(arguments, key: "parent_id").map { parentID in
                            let newTask = NewTask(title: title, description: description, timerMinutes: timer, subtasks: subtasks)
                            return .createTask(newTask, parentID: parentID)
                        }
                    }
                }
            }
        }
    }

    private static func parseCreateTasks(_ arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        guard let raw = arguments["tasks"], !isNull(raw) else {
            return .failure(BunnyToolError(message: "tasks is required"))
        }
        guard let array = raw as? [Any] else {
            return .failure(BunnyToolError(message: "tasks must be an array"))
        }
        guard !array.isEmpty else {
            return .failure(BunnyToolError(message: "tasks must not be empty"))
        }
        guard array.count <= 100 else {
            return .failure(BunnyToolError(message: "tasks must contain at most 100 items"))
        }

        var newTasks: [NewTask] = []
        newTasks.reserveCapacity(array.count)
        for item in array {
            guard let dict = item as? [String: Any] else {
                return .failure(BunnyToolError(message: "each task must be an object"))
            }
            switch parseNewTask(dict) {
            case .failure(let error):
                return .failure(error)
            case .success(let newTask):
                newTasks.append(newTask)
            }
        }

        return validatedOptionalUUID(arguments, key: "parent_id").map { parentID in
            .createTasks(newTasks, parentID: parentID)
        }
    }

    private static func parseNewTask(_ dict: [String: Any]) -> Result<NewTask, BunnyToolError> {
        validatedTitle(dict["title"]).flatMap { title in
            validatedDescription(dict).flatMap { description in
                validatedTimerMinutes(dict).flatMap { timer in
                    validatedSubtasks(dict).map { subtasks in
                        NewTask(title: title, description: description, timerMinutes: timer, subtasks: subtasks)
                    }
                }
            }
        }
    }

    private static func parseUpdateTask(_ arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        validatedUUID(arguments["id"], field: "id").flatMap { id in
            validatedOptionalTitle(arguments).flatMap { title in
                validatedDescription(arguments).flatMap { description in
                    validatedTimerMinutes(arguments).map { timer in
                        .updateTask(id: id, title: title, description: description, timerMinutes: timer)
                    }
                }
            }
        }
    }

    private static func parseCompleteTask(_ arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        validatedUUID(arguments["id"], field: "id").flatMap { id in
            validatedBool(arguments, key: "completed", default: true).map { completed in
                .completeTask(id: id, completed: completed)
            }
        }
    }

    private static func parseAddToShelf(_ arguments: [String: Any]) -> Result<BunnyToolCall, BunnyToolError> {
        validatedUUID(arguments["task_id"], field: "task_id").flatMap { taskID in
            validatedPaths(arguments).map { paths in
                .addToShelf(taskID: taskID, paths: paths)
            }
        }
    }

    // MARK: - Field validators

    private static func validatedTitle(_ raw: Any?) -> Result<String, BunnyToolError> {
        guard let raw, !isNull(raw) else {
            return .failure(BunnyToolError(message: "title is required"))
        }
        guard let string = raw as? String else {
            return .failure(BunnyToolError(message: "title must be a string"))
        }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(BunnyToolError(message: "title must not be empty"))
        }
        guard trimmed.count <= 200 else {
            return .failure(BunnyToolError(message: "title must be at most 200 characters"))
        }
        return .success(trimmed)
    }

    private static func validatedOptionalTitle(_ arguments: [String: Any], key: String = "title") -> Result<String?, BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else { return .success(nil) }
        return validatedTitle(raw).map { $0 }
    }

    private static func validatedDescription(_ arguments: [String: Any], key: String = "description") -> Result<String?, BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else { return .success(nil) }
        guard let string = raw as? String else {
            return .failure(BunnyToolError(message: "description must be a string"))
        }
        guard string.count <= 10_000 else {
            return .failure(BunnyToolError(message: "description must be at most 10000 characters"))
        }
        return .success(string)
    }

    private static func validatedTimerMinutes(_ arguments: [String: Any], key: String = "timer_minutes") -> Result<Double?, BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else { return .success(nil) }
        guard let value = numberValue(raw) else {
            return .failure(BunnyToolError(message: "timer_minutes must be a number"))
        }
        guard value > 0, value <= 1440 else {
            return .failure(BunnyToolError(message: "timer_minutes must be greater than 0 and at most 1440"))
        }
        return .success(value)
    }

    private static func validatedSubtasks(_ arguments: [String: Any], key: String = "subtasks") -> Result<[String], BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else { return .success([]) }
        guard let array = raw as? [Any] else {
            return .failure(BunnyToolError(message: "subtasks must be an array of strings"))
        }
        var titles: [String] = []
        titles.reserveCapacity(array.count)
        for item in array {
            switch validatedTitle(item) {
            case .failure(let error):
                return .failure(error)
            case .success(let title):
                titles.append(title)
            }
        }
        return .success(titles)
    }

    private static func validatedPaths(_ arguments: [String: Any], key: String = "paths") -> Result<[String], BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else {
            return .failure(BunnyToolError(message: "paths is required"))
        }
        guard let array = raw as? [Any] else {
            return .failure(BunnyToolError(message: "paths must be an array of strings"))
        }
        guard !array.isEmpty else {
            return .failure(BunnyToolError(message: "paths must not be empty"))
        }
        var paths: [String] = []
        paths.reserveCapacity(array.count)
        for item in array {
            guard let path = item as? String else {
                return .failure(BunnyToolError(message: "paths must be an array of strings"))
            }
            guard path.hasPrefix("/") else {
                return .failure(BunnyToolError(message: "paths must be absolute"))
            }
            paths.append(path)
        }
        return .success(paths)
    }

    private static func validatedBool(_ arguments: [String: Any], key: String, default defaultValue: Bool) -> Result<Bool, BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else { return .success(defaultValue) }
        guard let value = raw as? Bool else {
            return .failure(BunnyToolError(message: "\(key) must be a boolean"))
        }
        return .success(value)
    }

    private static func validatedUUID(_ raw: Any?, field: String) -> Result<UUID, BunnyToolError> {
        guard let raw, !isNull(raw), let string = raw as? String, let uuid = UUID(uuidString: string) else {
            return .failure(BunnyToolError(message: "\(field) must be a valid UUID"))
        }
        return .success(uuid)
    }

    private static func validatedOptionalUUID(_ arguments: [String: Any], key: String) -> Result<UUID?, BunnyToolError> {
        guard let raw = arguments[key], !isNull(raw) else { return .success(nil) }
        guard let string = raw as? String, let uuid = UUID(uuidString: string) else {
            return .failure(BunnyToolError(message: "\(key) must be a valid UUID"))
        }
        return .success(uuid)
    }

    // MARK: - Helpers

    private static func isNull(_ value: Any) -> Bool {
        value is NSNull
    }

    private static func numberValue(_ value: Any) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}
