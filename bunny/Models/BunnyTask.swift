import Foundation
import SwiftData

@Model
final class BunnyTask {
    var id: UUID = UUID()
    var title: String = ""
    var taskDescription: String = ""
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var isPinned: Bool = false
    var timerDuration: Double? = nil
    var timerStartedAt: Date? = nil
    var isExpanded: Bool = true
    var parentID: UUID? = nil
    /// Unused: the Archive is gone (`TaskActions.migrateArchived` empties it). Kept for the store schema.
    var archivedAt: Date? = nil
    var deletedAt: Date? = nil
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    // Agent handoff (spec §4). Raw values keep the store schema plain; use the computed accessors below.
    var agentHarness: String? = nil
    /// `agentHarness` was picked in the Hand off options card (outranks Settings' default); otherwise it only records the last run.
    var agentHarnessChosen: Bool = false
    var agentState: String = "idle"
    var agentSessionID: String? = nil
    /// The agent `agentSessionID` belongs to. `agentHarness` can move on (the options card picks the
    /// agent of the NEXT hand-off) while this session is still opened and messaged with its own agent.
    var agentSessionHarness: String? = nil
    var agentWorkingDirectory: String? = nil
    var agentActivity: String = ""
    var agentSummary: String = ""
    var agentQuestionData: Data? = nil
    var agentStartedAt: Date? = nil
    var agentFinishedAt: Date? = nil
    var completedByAgent: Bool = false
    /// Per-run model/effort override (spec §2), kept so resumes use the same settings. nil = use Settings.
    var agentModel: String? = nil
    var agentEffort: String? = nil
    /// The folder picked for this note in the Hand off options card: a path, or
    /// `WorkingDirectoryResolver.bunnyFolderChoice`. nil = attachments, then Settings (v3 spec §7 "Folder").
    var agentFolderChoice: String? = nil
    /// The short conversation with the agent (`AgentThread`, JSON): messages sent from Bunny and the agent's replies.
    var agentThreadData: Data? = nil
    /// When the agent part of this note was last shown; an agent message after it is unread.
    var agentSeenAt: Date? = nil

    init(title: String, parentID: UUID? = nil, sortOrder: Int = 0) {
        self.title = title
        self.parentID = parentID
        self.sortOrder = sortOrder
    }

    /// In the notes list: not in Trash.
    var isLive: Bool { deletedAt == nil }
    var isSubtask: Bool { parentID != nil }
    var hasTimer: Bool { timerDuration != nil }

    var remainingSeconds: Double {
        guard let duration = timerDuration else { return 0 }
        guard let startedAt = timerStartedAt else { return duration }
        return max(0, duration - Date().timeIntervalSince(startedAt))
    }

    var isTimerExpired: Bool {
        timerDuration != nil && timerStartedAt != nil && remainingSeconds <= 0
    }

    var isTimerRunning: Bool {
        timerStartedAt != nil && !isTimerExpired
    }

    var formattedRemaining: String {
        let total = Int(remainingSeconds)
        if total >= 3600 {
            return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
        } else {
            return String(format: "%02d:%02d", total / 60, total % 60)
        }
    }

    // MARK: - Agent accessors

    var runState: AgentRunState {
        get { AgentRunState(rawValue: agentState) ?? .idle }
        set { agentState = newValue.rawValue }
    }

    var harness: AgentHarness? {
        agentHarness.flatMap(AgentHarness.init(rawValue:))
    }

    /// Main-actor: `AgentQuestion`'s `Decodable` conformance is main-actor-isolated in the app target
    /// (default isolation). All callers (panel, supervisor) are on the main actor.
    @MainActor
    var pendingQuestion: AgentQuestion? {
        guard let agentQuestionData else { return nil }
        return try? JSONDecoder().decode(AgentQuestion.self, from: agentQuestionData)
    }
}
