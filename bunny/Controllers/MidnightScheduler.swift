import Foundation
import SwiftData

/// Runs note housekeeping — completed notes to Trash (`notes.completedRetention`) and the Trash purge
/// (`trash.retentionDays`) — at launch, at midnight, and hourly.
final class MidnightScheduler {
    static let shared = MidnightScheduler()
    private var timer: Timer?
    private var hourlyTimer: Timer?
    var modelContext: ModelContext?

    private init() {}

    func schedule() {
        runHousekeeping()
        scheduleNext()
        hourlyTimer?.invalidate()
        let hourly = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runHousekeeping() }
        }
        RunLoop.main.add(hourly, forMode: .common)
        hourlyTimer = hourly
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
                self?.runHousekeeping()
                self?.scheduleNext()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Also run when a retention setting changes.
    func runHousekeeping() {
        guard let context = modelContext else { return }
        TaskActions.trashExpiredCompleted(in: context)
        TaskActions.purgeExpiredTrash(in: context)
        ShelfService.removeEmptyFolders()
    }
}
