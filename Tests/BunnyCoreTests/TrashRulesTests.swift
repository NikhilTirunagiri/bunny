import Foundation
import Testing
@testable import BunnyCore

struct TrashRulesTests {
    private static let day: TimeInterval = 86_400
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    // MARK: - Days left / expiry

    @Test func daysLeftRoundsUp() {
        #expect(TrashRules.daysLeft(deletedAt: t0, retentionDays: 30, now: t0) == 30)
        #expect(TrashRules.daysLeft(deletedAt: t0, retentionDays: 30, now: t0.addingTimeInterval(Self.day + 1)) == 29)
        #expect(TrashRules.daysLeft(deletedAt: t0, retentionDays: 30, now: t0.addingTimeInterval(29 * Self.day + 1)) == 1)
    }

    @Test func daysLeftIsZeroAtAndAfterTheBoundary() {
        #expect(TrashRules.daysLeft(deletedAt: t0, retentionDays: 30, now: t0.addingTimeInterval(30 * Self.day)) == 0)
        #expect(TrashRules.daysLeft(deletedAt: t0, retentionDays: 30, now: t0.addingTimeInterval(90 * Self.day)) == 0)
    }

    @Test func expiryBoundary() {
        let boundary = t0.addingTimeInterval(7 * Self.day)
        #expect(!TrashRules.isExpired(deletedAt: t0, retentionDays: 7, now: boundary.addingTimeInterval(-1)))
        #expect(TrashRules.isExpired(deletedAt: t0, retentionDays: 7, now: boundary))
    }

    @Test func neverExpires() {
        #expect(!TrashRules.isExpired(deletedAt: t0, retentionDays: nil, now: t0.addingTimeInterval(10_000 * Self.day)))
    }

    // MARK: - Purge

    @Test func purgesExpiredAndSubtasksOfPurgedParents() {
        let parent = UUID(), child = UUID(), grandchild = UUID()
        let freshTrashed = UUID(), live = UUID(), orphanChild = UUID()
        let old = t0.addingTimeInterval(-40 * Self.day)
        let recent = t0.addingTimeInterval(-1 * Self.day)
        let records = [
            TrashRules.Record(id: parent, parentID: nil, deletedAt: old),
            TrashRules.Record(id: child, parentID: parent, deletedAt: recent),
            TrashRules.Record(id: grandchild, parentID: child, deletedAt: nil),
            TrashRules.Record(id: freshTrashed, parentID: nil, deletedAt: recent),
            TrashRules.Record(id: live, parentID: nil, deletedAt: nil),
            TrashRules.Record(id: orphanChild, parentID: live, deletedAt: recent),
        ]
        let purged = TrashRules.idsToPurge(records, retentionDays: 30, now: t0)
        #expect(purged == [parent, child, grandchild])
    }

    @Test func purgesNothingWhenRetentionIsNever() {
        let id = UUID()
        let records = [TrashRules.Record(id: id, parentID: nil, deletedAt: t0.addingTimeInterval(-999 * Self.day))]
        #expect(TrashRules.idsToPurge(records, retentionDays: nil, now: t0).isEmpty)
    }

    // MARK: - Auto-archive

    @Test func midnightPolicyArchivesCompletionsFromBeforeToday() {
        let cal = calendar("America/New_York")
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 30))!
        let lastNight = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 23, minute: 59))!
        let thisMorning = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0, minute: 1))!
        #expect(TrashRules.isDueForArchive(completedAt: lastNight, policy: .atMidnight, now: now, calendar: cal))
        #expect(!TrashRules.isDueForArchive(completedAt: thisMorning, policy: .atMidnight, now: now, calendar: cal))
    }

    @Test func midnightPolicyAcrossDST() {
        // US spring-forward is 2026-03-08: that day has 23 hours.
        let cal = calendar("America/New_York")
        let now = cal.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let startOfDay = cal.startOfDay(for: now)
        #expect(TrashRules.isDueForArchive(completedAt: startOfDay.addingTimeInterval(-1), policy: .atMidnight, now: now, calendar: cal))
        #expect(!TrashRules.isDueForArchive(completedAt: startOfDay, policy: .atMidnight, now: now, calendar: cal))
    }

    @Test func after24HoursBoundary() {
        let cal = calendar("UTC")
        #expect(!TrashRules.isDueForArchive(completedAt: t0, policy: .after24Hours, now: t0.addingTimeInterval(Self.day - 1), calendar: cal))
        #expect(TrashRules.isDueForArchive(completedAt: t0, policy: .after24Hours, now: t0.addingTimeInterval(Self.day), calendar: cal))
    }

    @Test func neverPolicyNeverArchives() {
        #expect(!TrashRules.isDueForArchive(completedAt: t0, policy: .never, now: t0.addingTimeInterval(1_000 * Self.day), calendar: calendar("UTC")))
    }

    // MARK: - Archive to Trash

    @Test func archiveToTrashBoundary() {
        let boundary = t0.addingTimeInterval(14 * Self.day)
        #expect(!TrashRules.isDueForTrash(archivedAt: t0, afterDays: 14, now: boundary.addingTimeInterval(-1)))
        #expect(TrashRules.isDueForTrash(archivedAt: t0, afterDays: 14, now: boundary))
        #expect(!TrashRules.isDueForTrash(archivedAt: t0, afterDays: nil, now: t0.addingTimeInterval(1_000 * Self.day)))
    }
}
