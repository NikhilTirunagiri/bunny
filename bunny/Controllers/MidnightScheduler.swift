import Foundation
import SwiftData

final class MidnightScheduler {
    static let shared = MidnightScheduler()
    private var timer: Timer?
    var modelContext: ModelContext?

    private init() {}

    func schedule() {
        scheduleNext()
    }

    private func scheduleNext() {
        let calendar = Calendar.current
        guard let midnight = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) else { return }

        timer?.invalidate()
        let t = Timer(fire: midnight, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.archiveCompletedTasks()
                self?.scheduleNext()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func archiveCompletedTasks() {
        guard let context = modelContext else { return }
        let now = Date()
        guard let all = try? context.fetch(FetchDescriptor<BunnyTask>()) else { return }

        let toArchive = all.filter { $0.isCompleted && $0.archivedAt == nil }
        let archivedParentIDs = Set(toArchive.filter { $0.parentID == nil }.map { $0.id })

        for task in toArchive {
            // Stop any live agent first (archiving never leaves a process running).
            AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)
            task.archivedAt = now
            if task.isPinned {
                task.isPinned = false
                AppState.shared.pinnedTaskID = nil
            }
        }

        // Archive subtasks whose parent was just archived (mirrors TaskRowView.archiveTask)
        for task in all where task.archivedAt == nil {
            if let pid = task.parentID, archivedParentIDs.contains(pid) {
                AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)
                task.archivedAt = now
            }
        }

        try? context.save()
    }
}
