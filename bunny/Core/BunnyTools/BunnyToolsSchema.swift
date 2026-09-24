import Foundation

/// The MCP tool schema Bunny advertises via `tools/list`, and that `BunnyToolArguments` parses
/// arguments against. Field names are snake_case, matching MCP tool-call convention.
enum BunnyToolsSchema {
    static var tools: [[String: Any]] {
        [
            [
                "name": "list_tasks",
                "description": "List the user's Bunny tasks, optionally including completed ones.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "include_completed": [
                            "type": "boolean",
                            "description": "Include completed tasks. Defaults to false.",
                        ],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "create_task",
                "description": "Create a new Bunny task, optionally with subtasks or as a subtask of an existing task.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Task title, trimmed and capped at 200 characters.",
                        ],
                        "description": [
                            "type": "string",
                            "description": "Task description, capped at 10000 characters.",
                        ],
                        "parent_id": [
                            "type": "string",
                            "description": "UUID of the parent task, to create this as a subtask.",
                        ],
                        "timer_minutes": [
                            "type": "number",
                            "description": "Timer duration in minutes; must be greater than 0 and at most 1440. Not allowed with parent_id (subtasks have no timer).",
                        ],
                        "subtasks": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Titles of subtasks to create under this task (at most 50).",
                        ],
                    ],
                    "required": ["title"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "create_tasks",
                "description": "Create multiple Bunny tasks in one batch (at most 100), optionally all under the same parent task.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "tasks": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "title": ["type": "string"],
                                    "description": ["type": "string"],
                                    "timer_minutes": ["type": "number"],
                                    "subtasks": [
                                        "type": "array",
                                        "items": ["type": "string"],
                                        "description": "At most 50 subtask titles.",
                                    ],
                                ],
                                "required": ["title"],
                            ],
                            "description": "At most 100 tasks.",
                        ],
                        "parent_id": [
                            "type": "string",
                            "description": "UUID of the parent task for all created tasks (they then can't have timer_minutes or subtasks).",
                        ],
                    ],
                    "required": ["tasks"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "update_task",
                "description": "Update an existing Bunny task's title, description, or timer.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "UUID of the task to update."],
                        "title": ["type": "string", "description": "New title, trimmed and capped at 200 characters."],
                        "description": ["type": "string", "description": "New description, capped at 10000 characters."],
                        "timer_minutes": [
                            "type": ["number", "null"],
                            "description": "New timer duration in minutes (greater than 0, at most 1440), or 0 / null to remove the timer. Subtasks can't have timers.",
                        ],
                    ],
                    "required": ["id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "complete_task",
                "description": "Mark a Bunny task as completed or not completed.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string", "description": "UUID of the task."],
                        "completed": ["type": "boolean", "description": "Defaults to true."],
                    ],
                    "required": ["id"],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "add_to_shelf",
                "description": "Add file paths to a Bunny task's shelf.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "task_id": ["type": "string", "description": "UUID of the task."],
                        "paths": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "Absolute file paths.",
                        ],
                    ],
                    "required": ["task_id", "paths"],
                    "additionalProperties": false,
                ],
            ],
        ]
    }
}
