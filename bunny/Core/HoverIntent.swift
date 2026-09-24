import Foundation

/// Pure state machine deciding when the task side panel shows, switches, hides or stays locked.
/// Time is injected so it can be unit tested; the app calls `tick(now:)` at `nextDeadline`.
struct HoverIntent {
    enum Effect: Equatable { case none, show(UUID), hide }
    enum EscapeResult: Equatable { case unlocked, closePopover }

    static let dwell: TimeInterval = 0.35
    static let grace: TimeInterval = 0.25

    private(set) var shownTaskID: UUID?
    private(set) var lockedTaskID: UUID?
    private var hoveredRowID: UUID?
    private var pendingShow: (id: UUID, at: Date)?
    private var pendingHideAt: Date?
    private var pointerInPanel = false
    private var editing = false

    var nextDeadline: Date? {
        [pendingShow?.at, pendingHideAt].compactMap { $0 }.min()
    }

    mutating func rowEntered(_ id: UUID, now: Date) -> Effect {
        hoveredRowID = id
        pendingHideAt = nil
        if lockedTaskID != nil { return .none }
        if shownTaskID != nil {
            pendingShow = nil
            if shownTaskID == id { return .none }
            shownTaskID = id
            return .show(id)
        }
        pendingShow = (id, now.addingTimeInterval(Self.dwell))
        return .none
    }

    mutating func rowExited(_ id: UUID, now: Date) {
        if hoveredRowID == id { hoveredRowID = nil }
        if pendingShow?.id == id { pendingShow = nil }
        scheduleHideIfIdle(now: now)
    }

    mutating func panelEntered() {
        pointerInPanel = true
        pendingHideAt = nil
    }

    mutating func panelExited(now: Date) {
        pointerInPanel = false
        scheduleHideIfIdle(now: now)
    }

    mutating func setEditing(_ editing: Bool, now: Date) {
        self.editing = editing
        if editing { pendingHideAt = nil } else { scheduleHideIfIdle(now: now) }
    }

    mutating func rowClicked(_ id: UUID) -> Effect {
        if lockedTaskID == id {
            lockedTaskID = nil
            return .none
        }
        return lock(id)
    }

    mutating func lock(_ id: UUID) -> Effect {
        lockedTaskID = id
        pendingShow = nil
        pendingHideAt = nil
        let changed = shownTaskID != id
        shownTaskID = id
        return changed ? .show(id) : .none
    }

    mutating func fileDragEntered(_ id: UUID) -> Effect {
        pendingShow = nil
        pendingHideAt = nil
        if shownTaskID == id { return .none }
        shownTaskID = id
        return .show(id)
    }

    mutating func escape(now: Date) -> EscapeResult {
        if lockedTaskID != nil {
            lockedTaskID = nil
            scheduleHideIfIdle(now: now)
            return .unlocked
        }
        return .closePopover
    }

    mutating func popoverClosed() -> Effect {
        let wasShown = shownTaskID != nil
        self = HoverIntent()
        return wasShown ? .hide : .none
    }

    mutating func tick(now: Date) -> Effect {
        if let p = pendingShow, now >= p.at {
            pendingShow = nil
            shownTaskID = p.id
            return .show(p.id)
        }
        if let h = pendingHideAt, now >= h {
            pendingHideAt = nil
            shownTaskID = nil
            return .hide
        }
        return .none
    }

    private mutating func scheduleHideIfIdle(now: Date) {
        guard shownTaskID != nil, lockedTaskID == nil, !pointerInPanel, !editing, hoveredRowID == nil else { return }
        pendingHideAt = now.addingTimeInterval(Self.grace)
    }
}
