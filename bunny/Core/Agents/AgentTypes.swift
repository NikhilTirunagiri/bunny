import Foundation

/// Which coding-agent CLI a task is handed off to.
enum AgentHarness: String, Codable, CaseIterable, Sendable {
    case claudeCode, codex

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    var symbolName: String {
        switch self {
        case .claudeCode: return "sparkle"
        case .codex: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

/// Lifecycle of an agent run, persisted on the task.
enum AgentRunState: String, Codable, Sendable {
    /// `replied`: a turn ended without the agent declaring the task complete (`finished` is that).
    case idle, running, needsInput, replied, finished, failed, stopped, handedOff

    var isActive: Bool {
        self == .running || self == .needsInput
    }

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .running: return "Working…"
        case .needsInput: return "Needs your input"
        case .replied: return "Replied"
        case .finished: return "Done"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        case .handedOff: return "Opened in app"
        }
    }
}

/// Whether an agent asks before acting or proceeds autonomously.
enum AgentAutonomy: String, Codable, CaseIterable, Sendable {
    case autonomous, askFirst
}

/// Preferred app for "open this session" / "chat about this".
enum OpenInApp: String, Codable, CaseIterable, Sendable {
    case terminal, vscode
    /// The agent's own desktop app: Claude for Claude Code sessions, Codex for Codex sessions.
    case claudeApp, codexApp
    /// The app the owner picked with "Other App…" (its path and name are stored beside the choice).
    case custom

    var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .vscode: return "VS Code"
        case .claudeApp: return "Claude app"
        case .codexApp: return "Codex app"
        case .custom: return "Other App"
        }
    }

    /// How the installed app is found (`custom` has a stored path instead).
    var bundleIdentifier: String? {
        switch self {
        case .terminal: return "com.apple.Terminal"
        case .vscode: return "com.microsoft.VSCode"
        case .claudeApp: return "com.anthropic.claudefordesktop"
        case .codexApp: return "com.openai.codex"
        case .custom: return nil
        }
    }

    /// A desktop app only opens its own agent's sessions; everything else opens both.
    func supports(_ harness: AgentHarness) -> Bool {
        switch self {
        case .claudeApp: return harness == .claudeCode
        case .codexApp: return harness == .codex
        default: return true
        }
    }

    /// The built-in targets of `harness`, in menu order.
    static func builtIn(for harness: AgentHarness) -> [OpenInApp] {
        [.terminal, .vscode, harness == .claudeCode ? .claudeApp : .codexApp]
    }

    /// What the old single "Open sessions in" value becomes for each agent. Ghostty and Cursor are no
    /// longer built in: they become the custom app, by bundle identifier (Terminal when not installed).
    enum Migrated: Equatable {
        case builtIn(OpenInApp)
        case customApp(bundleIdentifier: String)
    }

    static func migrated(from old: String?) -> Migrated {
        switch old {
        case "vscode": return .builtIn(.vscode)
        case "ghostty": return .customApp(bundleIdentifier: "com.mitchellh.ghostty")
        case "cursor": return .customApp(bundleIdentifier: "com.todesktop.230313mzl4w4u92")
        default: return .builtIn(.terminal)
        }
    }
}

/// A single selectable option within an `AgentQuestionItem`.
struct AgentQuestionOption: Codable, Equatable, Sendable {
    var label: String
    var detail: String?
}

/// One question within an `AgentQuestion` (Claude's AskUserQuestion can carry several at once).
struct AgentQuestionItem: Codable, Equatable, Sendable {
    /// Claude: the exact question text. Codex marker questions: the literal string "answer".
    var key: String
    var header: String?
    var question: String
    var options: [AgentQuestionOption]
    var multiSelect: Bool
    /// True for Claude's AskUserQuestion tool, and for marker questions that carry options.
    var allowsOther: Bool
}

/// A question the agent is blocked on, awaiting the owner's answer.
struct AgentQuestion: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case choices, freeform, approval
    }

    var kind: Kind
    /// choices: 1+ items. freeform: exactly 1 item with no options. approval: empty.
    var items: [AgentQuestionItem]
    var approvalTitle: String?
    var approvalDetail: String?
    /// Claude control request_id, or Codex JSON-RPC id rendered as a string.
    var requestID: String?
    /// Codex server-request method (approvals only).
    var method: String?
    /// Claude's original tool input JSON, needed to build `updatedInput` when answering.
    var rawInput: Data?
}

/// The owner's answer to a pending `AgentQuestion`.
struct AgentAnswer: Codable, Equatable, Sendable {
    /// item.key -> chosen option labels and/or typed free text.
    var selections: [String: [String]]
    /// Approvals only.
    var approved: Bool?

    /// Human-readable answer used for Codex follow-up turns and resumed sessions.
    func summary(for question: AgentQuestion) -> String {
        if let approved {
            return approved ? "Allowed" : "Denied"
        }
        if question.items.count == 1, let item = question.items.first {
            return (selections[item.key] ?? []).joined(separator: ", ")
        }
        return question.items.map { item in
            "\(item.question): \((selections[item.key] ?? []).joined(separator: ", "))"
        }.joined(separator: "\n")
    }
}

/// Everything a task knows, handed to the agent as context.
struct AgentBrief: Equatable, Sendable {
    struct Subtask: Equatable, Sendable {
        var title: String
        var done: Bool
    }

    struct ShelfEntry: Equatable, Sendable {
        var path: String
        var isDirectory: Bool
    }

    var title: String
    var description: String
    var subtasks: [Subtask]
    var shelf: [ShelfEntry]
    /// nil = no timer.
    var deadline: Date?
    var workingDirectory: String
    var extraDirectories: [String]
}

/// A single event streamed from a running agent, delivered on the main queue.
enum AgentEvent: Equatable, Sendable {
    case sessionStarted(String)
    /// The model the CLI says the session runs on (Claude Code's `system/init`).
    case modelReported(String)
    case activity(String)
    case question(AgentQuestion)
    case turnFinished(text: String, success: Bool)
    case failed(String)
    case exited(Int32)
}
