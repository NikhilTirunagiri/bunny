import CoreGraphics

enum PanelSide: Equatable { case left, right }

/// Computes where the task side panel sits relative to the popover window (AppKit screen coordinates, origin bottom-left).
enum PanelPlacement {
    static let defaultWidth: CGFloat = 300
    static let defaultGap: CGFloat = 8

    static func frame(popover: CGRect, visible: CGRect,
                      width: CGFloat = defaultWidth, gap: CGFloat = defaultGap) -> (frame: CGRect, side: PanelSide) {
        let height = min(popover.height, visible.height)
        let y = min(max(popover.maxY - height, visible.minY), visible.maxY - height)
        let leftX = popover.minX - gap - width
        if leftX >= visible.minX {
            return (CGRect(x: leftX, y: y, width: width, height: height), .left)
        }
        let rightX = popover.maxX + gap
        if rightX + width <= visible.maxX {
            return (CGRect(x: rightX, y: y, width: width, height: height), .right)
        }
        let clampedX = min(max(leftX, visible.minX), visible.maxX - width)
        return (CGRect(x: clampedX, y: y, width: width, height: height), .left)
    }
}
