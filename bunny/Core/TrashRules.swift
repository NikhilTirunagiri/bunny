import Foundation

/// Pure retention rules for Trash and for completed notes. Time is injected; no model types.
enum TrashRules {
    /// How long a completed note stays in the Completed group before it moves to Trash.
    enum CompletedRetention: Equatable { case after24Hours, after7Days, never }

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

    /// A completed note is due for Trash once it has been completed for the whole retention period.
    static func isDueForTrash(completedAt: Date, retention: CompletedRetention, now: Date) -> Bool {
        switch retention {
        case .after24Hours: return now.timeIntervalSince(completedAt) >= day
        case .after7Days: return now.timeIntervalSince(completedAt) >= 7 * day
        case .never: return false
        }
    }
}
