import Foundation
import SwiftData

/// Runs note housekeeping — auto-archive (`notes.autoArchive`) and the Trash purge
/// (`trash.retentionDays`) — at launch, at midnight, and hourly (for the 24-hour policy and missed midnights).
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

    private func runHousekeeping() {
        guard let context = modelContext else { return }
        TaskActions.autoArchive(in: context)
        TaskActions.purgeExpiredTrash(in: context)
    }
}
