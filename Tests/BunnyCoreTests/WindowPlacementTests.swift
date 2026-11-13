import Testing
import CoreGraphics
@testable import BunnyCore

struct WindowPlacementTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
    /// A status item button in a 25 pt menu bar on a 1440×900 screen.
    let anchor = CGRect(x: 900, y: 875, width: 30, height: 25)

    private func place(_ anchor: CGRect, in visible: CGRect, height: CGFloat = 480) -> (frame: CGRect, card: CGRect, noteSide: PanelSide) {
        WindowPlacement.frame(anchor: anchor, visible: visible, height: height)
    }

    @Test func listHangsRightOfTheStatusItemWithTheNoteOnItsLeft() {
        let r = place(anchor, in: visible)
        #expect(r.noteSide == .left)
        #expect(WindowPlacement.listFrame(card: r.card, noteSide: r.noteSide)
                == CGRect(x: 900 - 8, y: 875 - 5 - 480, width: 340, height: 480))
        #expect(r.card == CGRect(x: 564, y: 390, width: 668, height: 480))  // 892 - 328
    }

    @Test func windowIsTheCardPlusShadowRoomAndStopsAtTheMenuBar() {
        let r = place(anchor, in: visible)
        #expect(r.frame == CGRect(x: 564 - 24, y: 390 - 24, width: 668 + 48, height: 480 + 24 + 5))
        #expect(r.frame.maxY == visible.maxY)
    }

    @Test func noteGoesRightWhenNoRoomLeft() {
        let leftItem = CGRect(x: 200, y: 875, width: 30, height: 25)
        let r = place(leftItem, in: visible)
        #expect(r.noteSide == .right)
        #expect(r.card.minX == 192)
        #expect(WindowPlacement.listFrame(card: r.card, noteSide: r.noteSide).minX == 192)
    }

    @Test func listClampsToTheRightEdge() {
        let edgeItem = CGRect(x: 1430, y: 875, width: 30, height: 25)
        let r = place(edgeItem, in: visible)
        #expect(r.noteSide == .left)
        #expect(r.card.maxX == 1440)
        #expect(WindowPlacement.listFrame(card: r.card, noteSide: r.noteSide).minX == 1100)
    }

    @Test func noteGoesLeftOfAListClampedAtTheRightEdge() {
        let edgeItem = CGRect(x: 1300, y: 875, width: 30, height: 25)
        let r = place(edgeItem, in: visible)
        #expect(r.noteSide == .left)
        #expect(r.card == CGRect(x: 1440 - 668, y: 875 - 5 - 480, width: 668, height: 480))
    }

    @Test func clampsInsideVisibleWhenNeitherSideFits() {
        let narrow = CGRect(x: 0, y: 0, width: 600, height: 875)
        let item = CGRect(x: 400, y: 875, width: 30, height: 25)
        let r = place(item, in: narrow)
        #expect(r.noteSide == .left)
        #expect(r.card.minX == 0)
    }

    @Test func heightClampsToVisibleFrame() {
        let short = CGRect(x: 0, y: 0, width: 1440, height: 300)
        let item = CGRect(x: 1200, y: 300, width: 30, height: 25)
        let r = place(item, in: short)
        #expect(r.card.height == 300)
        #expect(r.card.minY == 0)
    }

    @Test func respectsVisibleOriginOnSecondaryScreen() {
        let screen2 = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let item = CGRect(x: -300, y: 1055, width: 30, height: 25)
        let r = place(item, in: screen2)
        #expect(r.noteSide == .left)
        #expect(r.card.maxX == 0)
        let item2 = CGRect(x: -1000, y: 1055, width: 30, height: 25)
        let r2 = place(item2, in: screen2)
        #expect(r2.noteSide == .left)
        #expect(r2.card.maxX == -668)  // list at -1000 - 8
        #expect(r2.card.minX == -1336)
    }
}
