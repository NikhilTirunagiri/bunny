import Testing
import Foundation
@testable import BunnyCore

struct HoverIntentTests {
    let a = UUID(), b = UUID()
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func dwellBeforeFirstShow() {
        var h = HoverIntent()
        #expect(h.rowEntered(a, now: t0) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(0.2)) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(0.36)) == .show(a))
        #expect(h.shownTaskID == a)
    }

    @Test func leavingBeforeDwellCancelsShow() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0)
        h.rowExited(a, now: t0.addingTimeInterval(0.1))
        #expect(h.tick(now: t0.addingTimeInterval(1)) == .none)
        #expect(h.shownTaskID == nil)
    }

    @Test func switchesImmediatelyOnceVisible() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(0.5))
        #expect(h.rowEntered(b, now: t0.addingTimeInterval(0.55)) == .show(b))
        #expect(h.tick(now: t0.addingTimeInterval(2)) == .none) // pending hide was cancelled
    }

    @Test func hidesAfterGraceWhenPointerLeaves() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(1))
        #expect(h.tick(now: t0.addingTimeInterval(1.2)) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(1.26)) == .hide)
        #expect(h.shownTaskID == nil)
    }

    @Test func pointerInPanelKeepsItOpen() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(1))
        h.panelEntered()
        #expect(h.tick(now: t0.addingTimeInterval(5)) == .none)
        h.panelExited(now: t0.addingTimeInterval(6))
        #expect(h.tick(now: t0.addingTimeInterval(6.3)) == .hide)
    }

    @Test func editingBlocksHide() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0); _ = h.tick(now: t0.addingTimeInterval(0.4))
        h.rowExited(a, now: t0.addingTimeInterval(0.9))
        h.panelEntered()
        h.setEditing(true, now: t0.addingTimeInterval(1))
        h.panelExited(now: t0.addingTimeInterval(2))
        #expect(h.tick(now: t0.addingTimeInterval(10)) == .none)
        h.setEditing(false, now: t0.addingTimeInterval(11))
        #expect(h.tick(now: t0.addingTimeInterval(11.3)) == .hide)
    }

    @Test func clickLocksAndHoverDoesNotSteal() {
        var h = HoverIntent()
        #expect(h.rowClicked(a) == .show(a))
        #expect(h.lockedTaskID == a)
        #expect(h.rowEntered(b, now: t0) == .none)
        h.rowExited(b, now: t0.addingTimeInterval(0.1))
        #expect(h.tick(now: t0.addingTimeInterval(5)) == .none)
        #expect(h.shownTaskID == a)
    }

    @Test func clickingLockedRowUnlocks() {
        var h = HoverIntent()
        _ = h.rowClicked(a)
        _ = h.rowClicked(a)
        #expect(h.lockedTaskID == nil)
        #expect(h.shownTaskID == a)
    }

    @Test func escapeUnlocksThenCloses() {
        var h = HoverIntent()
        _ = h.rowClicked(a)
        #expect(h.escape(now: t0) == .unlocked)
        #expect(h.escape(now: t0) == .closePopover)
    }

    @Test func fileDragShowsImmediately() {
        var h = HoverIntent()
        #expect(h.fileDragEntered(b) == .show(b))
    }

    @Test func popoverCloseResetsEverything() {
        var h = HoverIntent()
        _ = h.rowClicked(a)
        #expect(h.popoverClosed() == .hide)
        #expect(h.shownTaskID == nil && h.lockedTaskID == nil && h.nextDeadline == nil)
    }

    @Test func nextDeadlineReflectsPendingWork() {
        var h = HoverIntent()
        _ = h.rowEntered(a, now: t0)
        #expect(h.nextDeadline == t0.addingTimeInterval(HoverIntent.dwell))
    }
}
