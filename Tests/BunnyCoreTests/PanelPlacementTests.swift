import Testing
import CoreGraphics
@testable import BunnyCore

struct PanelPlacementTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func placesLeftWithGapAndTopAligned() {
        let popover = CGRect(x: 1000, y: 395, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: visible)
        #expect(r.side == .left)
        #expect(r.frame == CGRect(x: 1000 - 8 - 300, y: 395, width: 300, height: 480))
    }

    @Test func flipsRightWhenNoRoomLeft() {
        let popover = CGRect(x: 100, y: 395, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: visible)
        #expect(r.side == .right)
        #expect(r.frame.minX == 448)
    }

    @Test func clampsInsideVisibleWhenNeitherFits() {
        let narrow = CGRect(x: 0, y: 0, width: 700, height: 875)
        let popover = CGRect(x: 200, y: 395, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: narrow)
        #expect(r.side == .left)
        #expect(r.frame.minX == 0)
        #expect(r.frame.width == 300)
    }

    @Test func respectsVisibleOriginOnSecondaryScreen() {
        let screen2 = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let popover = CGRect(x: -500, y: 575, width: 340, height: 480)
        let r = PanelPlacement.frame(popover: popover, visible: screen2)
        #expect(r.side == .left)
        #expect(r.frame.minX == -808)
    }
}
