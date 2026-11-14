import CoreGraphics

enum PanelSide: Equatable { case left, right }

/// Placement of the main window under the status item (AppKit screen coordinates, origin bottom-left).
/// `card` is the visible part with a note open: the list plus the note side. The list's left edge sits
/// just left of the status item's left edge (the window hangs to the right of it, like Maccy), clamped to
/// the visible frame, and the note side goes on its left, or on its right when the left has no room.
/// `frame` is the window: the card plus transparent room for its shadow. It stays the same while the
/// window is open; the note side is revealed inside it, so the list never moves.
enum WindowPlacement {
    static let listWidth: CGFloat = 340
    static let noteWidth: CGFloat = 328
    /// Space between the menu bar and the card's top edge. The window takes only this much above the
    /// card, so it never reaches over the menu bar.
    static let gap: CGFloat = 5
    /// How far the list's left edge sits left of the status item's left edge.
    static let leadingInset: CGFloat = 8
    /// Transparent room left, right and below the card for its shadow.
    static let shadowMargin: CGFloat = 24

    static func frame(anchor: CGRect, visible: CGRect,
                      height: CGFloat) -> (frame: CGRect, card: CGRect, noteSide: PanelSide) {
        let h = min(height, visible.height)
        let top = min(anchor.minY, visible.maxY) - gap
        let y = max(top - h, visible.minY)
        let listX = max(min(anchor.minX - leadingInset, visible.maxX - listWidth), visible.minX)
        let width = listWidth + noteWidth
        let x: CGFloat
        let side: PanelSide
        if listX - noteWidth >= visible.minX {
            (x, side) = (listX - noteWidth, .left)
        } else if listX + width <= visible.maxX {
            (x, side) = (listX, .right)
        } else {
            // Neither side fits (very narrow screen): keep the note on the left and clamp the card.
            (x, side) = (max(min(listX - noteWidth, visible.maxX - width), visible.minX), .left)
        }
        let card = CGRect(x: x, y: y, width: width, height: h)
        let frame = CGRect(x: card.minX - shadowMargin, y: card.minY - shadowMargin,
                           width: width + 2 * shadowMargin, height: h + shadowMargin + gap)
        return (frame, card, side)
    }

    /// The list column: the card's edge away from the note side.
    static func listFrame(card: CGRect, noteSide: PanelSide) -> CGRect {
        CGRect(x: noteSide == .left ? card.maxX - listWidth : card.minX, y: card.minY,
               width: listWidth, height: card.height)
    }
}
