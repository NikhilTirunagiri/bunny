import AppKit

/// Transparent view covering the status item button. A file dragged onto the menu bar icon opens the popover
/// so the drag can continue onto a task. Clicks are forwarded to the button's normal action.
final class StatusItemDropView: NSView {
    var onDragEntered: (() -> Void)?
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onDragEntered?()
        return []     // the icon itself never accepts the drop
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func rightMouseDown(with event: NSEvent) { onClick?() }
}
