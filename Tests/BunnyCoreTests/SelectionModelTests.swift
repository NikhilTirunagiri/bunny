import Foundation
import Testing
@testable import BunnyCore

struct SelectionModelTests {
    private let ids = (0..<5).map { _ in UUID() }
    private var a: UUID { ids[0] }
    private var b: UUID { ids[1] }
    private var c: UUID { ids[2] }
    private var d: UUID { ids[3] }
    private var e: UUID { ids[4] }

    private func apply(_ input: SelectionModel.Input, to selection: SelectionModel.Selection = .init()) -> SelectionModel.Selection {
        SelectionModel.apply(input, to: selection, visible: ids)
    }

    // MARK: - Click

    @Test func clickSelectsOnlyThatNote() {
        let start = apply(.toggle(a))
        let next = apply(.click(c), to: apply(.toggle(b), to: start))
        #expect(next.ids == [c])
        #expect(next.single == c)
    }

    @Test func clickOnTheOnlySelectedNoteDeselects() {
        let selected = apply(.click(b))
        let next = apply(.click(b), to: selected)
        #expect(next.ids.isEmpty)
        #expect(next.single == nil)
    }

    @Test func clickOnANoteInAMultiSelectionSelectsJustIt() {
        let multi = apply(.toggle(b), to: apply(.click(a)))
        #expect(apply(.click(b), to: multi).ids == [b])
    }

    @Test func selectNeverDeselects() {
        let selected = apply(.click(b))
        #expect(apply(.select(b), to: selected).ids == [b])
    }

    // MARK: - ⌘-click

    @Test func commandClickToggles() {
        var s = apply(.click(a))
        s = apply(.toggle(c), to: s)
        #expect(s.ids == [a, c])
        #expect(s.single == nil)
        s = apply(.toggle(a), to: s)
        #expect(s.ids == [c])
        #expect(s.single == c)
    }

    // MARK: - Shift-click

    @Test func shiftClickSelectsTheRangeFromTheAnchor() {
        let s = apply(.extend(d), to: apply(.click(b)))
        #expect(s.ids == [b, c, d])
    }

    @Test func shiftClickUpwardsAndAgainKeepsTheAnchor() {
        var s = apply(.click(c))
        s = apply(.extend(a), to: s)
        #expect(s.ids == [a, b, c])
        s = apply(.extend(e), to: s)
        #expect(s.ids == [c, d, e])
    }

    @Test func shiftClickWithoutAnchorSelectsOne() {
        #expect(apply(.extend(c)).ids == [c])
    }

    @Test func shiftClickAfterCommandClickAnchorsOnTheToggledNote() {
        let s = apply(.extend(e), to: apply(.toggle(d), to: apply(.click(a))))
        #expect(s.ids == [d, e])
    }

    // MARK: - Arrows

    @Test func downWithNothingSelectedSelectsTheFirst() {
        #expect(apply(.down).ids == [a])
        #expect(apply(.up).ids == [e])
    }

    @Test func arrowsMoveASingleSelection() {
        #expect(apply(.down, to: apply(.click(b))).ids == [c])
        #expect(apply(.up, to: apply(.click(b))).ids == [a])
    }

    @Test func arrowsStopAtTheEnds() {
        #expect(apply(.up, to: apply(.click(a))).ids == [a])
        #expect(apply(.down, to: apply(.click(e))).ids == [e])
    }

    @Test func arrowsMoveFromTheLastClickedNoteOfARange() {
        let range = apply(.extend(d), to: apply(.click(b)))
        #expect(apply(.down, to: range).ids == [e])
    }

    @Test func arrowFromAHiddenNoteStartsOver() {
        let hidden = UUID()
        let s = SelectionModel.Selection(ids: [hidden], anchor: hidden, cursor: hidden)
        #expect(apply(.down, to: s).ids == [a])
    }

    @Test func arrowsOnAnEmptyListClear() {
        let s = SelectionModel.apply(.down, to: apply(.click(a)), visible: [])
        #expect(s.ids.isEmpty)
    }

    // MARK: - Select all / remove / clear

    @Test func selectAll() {
        #expect(apply(.selectAll, to: apply(.click(c))).ids == Set(ids))
    }

    @Test func removedIDsLeaveTheSelection() {
        let range = apply(.extend(d), to: apply(.click(b)))
        let s = apply(.removed([c, d]), to: range)
        #expect(s.ids == [b])
        #expect(s.cursor == nil)
        #expect(s.anchor == b)
    }

    @Test func clearKeepsTheCursorForReturn() {
        let s = apply(.clear, to: apply(.click(c)))
        #expect(s.ids.isEmpty)
        #expect(s.cursor == c)
    }
}
