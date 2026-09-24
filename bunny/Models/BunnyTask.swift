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
    var archivedAt: Date? = nil
    var createdAt: Date = Date()
    var sortOrder: Int = 0

    init(title: String, parentID: UUID? = nil, sortOrder: Int = 0) {
        self.title = title
        self.parentID = parentID
        self.sortOrder = sortOrder
    }

    var isArchived: Bool { archivedAt != nil }
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
}
