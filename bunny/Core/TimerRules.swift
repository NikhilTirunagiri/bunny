import Foundation

/// Pure rules for note timers. Time is injected; no model types.
enum TimerRules {
    /// A started timer.
    struct Started: Equatable {
        var id: UUID
        var startedAt: Date
        var duration: TimeInterval

        var end: Date { startedAt.addingTimeInterval(duration) }
    }

    /// The timers that ran out since the last check: those ending in `(lastCheck, now]`. Successive
    /// checks cover time with no gap and no overlap, so every expiry is reported exactly once, however
    /// late the check comes (sleep) and whether or not the note is shown in the menu bar. A timer that
    /// ran out before the first check (Bunny was not running) is not reported late; a restarted one
    /// is reported again when it ends.
    static func justExpired(_ timers: [Started], since lastCheck: Date, now: Date) -> [UUID] {
        timers.filter { $0.end > lastCheck && $0.end <= now }.map(\.id)
    }

    /// Whether starting a timer on `note` puts it in the menu bar by default: yes, in place of
    /// whatever is shown there, unless that is another note whose timer is still running.
    static func takesMenuBar(note: UUID, shown: UUID?, shownTimerRunning: Bool) -> Bool {
        shown == nil || shown == note || !shownTimerRunning
    }
}
