import Foundation

/// Pure retention rules for Trash and auto-archive. Time and calendar are injected; no model types.
enum TrashRules {
    /// Completed items move to the archive on this schedule.
    enum AutoArchivePolicy: Equatable { case atMidnight, after24Hours, never }

    /// The minimum a purge needs to know about a task.
    struct Record: Equatable {
        var id: UUID
        var parentID: UUID?
        var deletedAt: Date?
    }

    private static let day: TimeInterval = 86_400

    /// Whole days left before a trashed item is purged, rounded up, never negative.
    static func daysLeft(deletedAt: Date, retentionDays: Int, now: Date) -> Int {
        let remaining = deletedAt.addingTimeInterval(Double(retentionDays) * day).timeIntervalSince(now)
        return max(0, Int((remaining / day).rounded(.up)))
    }

    /// `retentionDays` nil = "Never": nothing expires.
    static func isExpired(deletedAt: Date, retentionDays: Int?, now: Date) -> Bool {
        guard let retentionDays else { return false }
        return daysLeft(deletedAt: deletedAt, retentionDays: retentionDays, now: now) == 0
    }

    /// Expired trashed items, plus every descendant of a purged item.
    static func idsToPurge(_ records: [Record], retentionDays: Int?, now: Date) -> Set<UUID> {
        var purged = Set(records.compactMap { record -> UUID? in
            guard let deletedAt = record.deletedAt,
                  isExpired(deletedAt: deletedAt, retentionDays: retentionDays, now: now) else { return nil }
            return record.id
        })
        var added = true
        while added {
            added = false
            for record in records where !purged.contains(record.id) {
                if let parentID = record.parentID, purged.contains(parentID) {
                    purged.insert(record.id)
                    added = true
                }
            }
        }
        return purged
    }

    /// `atMidnight`: completed before the start of today (in `calendar`). `after24Hours`: a full 24 h ago.
    static func isDueForArchive(completedAt: Date, policy: AutoArchivePolicy, now: Date, calendar: Calendar) -> Bool {
        switch policy {
        case .atMidnight: return completedAt < calendar.startOfDay(for: now)
        case .after24Hours: return now.timeIntervalSince(completedAt) >= day
        case .never: return false
        }
    }

    /// An archived item moves to Trash after `afterDays` (nil = "Never").
    static func isDueForTrash(archivedAt: Date, afterDays: Int?, now: Date) -> Bool {
        guard let afterDays else { return false }
        return now.timeIntervalSince(archivedAt) >= Double(afterDays) * day
    }
}
