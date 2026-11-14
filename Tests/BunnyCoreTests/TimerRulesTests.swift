import Foundation
import Testing
@testable import BunnyCore

struct TimerRulesTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let a = UUID(), b = UUID()

    private func timer(_ id: UUID, endsAfter seconds: TimeInterval) -> TimerRules.Started {
        TimerRules.Started(id: id, startedAt: t0, duration: seconds)
    }

    @Test func reportsATimerOnceWhenItEnds() {
        let timers = [timer(a, endsAfter: 60)]
        #expect(TimerRules.justExpired(timers, since: t0.addingTimeInterval(58), now: t0.addingTimeInterval(59)).isEmpty)
        #expect(TimerRules.justExpired(timers, since: t0.addingTimeInterval(59), now: t0.addingTimeInterval(60)) == [a])
        #expect(TimerRules.justExpired(timers, since: t0.addingTimeInterval(60), now: t0.addingTimeInterval(61)).isEmpty)
    }

    @Test func reportsEveryTimerThatEndedSinceTheLastCheck() {
        // One late check (e.g. after sleep) covers both; a timer still running is left out.
        let timers = [timer(a, endsAfter: 60), timer(b, endsAfter: 90), timer(UUID(), endsAfter: 600)]
        #expect(TimerRules.justExpired(timers, since: t0, now: t0.addingTimeInterval(300)) == [a, b])
    }

    @Test func aTimerThatEndedBeforeTheFirstCheckIsNotReported() {
        let timers = [timer(a, endsAfter: 60)]
        #expect(TimerRules.justExpired(timers, since: t0.addingTimeInterval(3600), now: t0.addingTimeInterval(3601)).isEmpty)
    }

    @Test func aRestartedTimerIsReportedAgain() {
        let restarted = TimerRules.Started(id: a, startedAt: t0.addingTimeInterval(100), duration: 60)
        #expect(TimerRules.justExpired([restarted], since: t0.addingTimeInterval(159), now: t0.addingTimeInterval(160)) == [a])
    }

    @Test func startingATimerTakesTheMenuBarUnlessAnotherRunningTimerIsShown() {
        #expect(TimerRules.takesMenuBar(note: a, shown: nil, shownTimerRunning: false))
        #expect(TimerRules.takesMenuBar(note: a, shown: a, shownTimerRunning: true))
        #expect(TimerRules.takesMenuBar(note: a, shown: b, shownTimerRunning: false))
        #expect(!TimerRules.takesMenuBar(note: a, shown: b, shownTimerRunning: true))
    }
}
