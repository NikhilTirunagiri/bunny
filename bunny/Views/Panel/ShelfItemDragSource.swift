import AppKit
import SwiftUI

/// Transparent AppKit overlay for a shelf row: starts file drags (copy outside the app, move inside it),
/// opens on double-click, shows the context menu, and reports hover.
struct ShelfItemDragSource: NSViewRepresentable {
    let url: URL?                        // nil = missing file → not draggable
    var onDragEnded: (NSDragOperation) -> Void
    var onDoubleClick: () -> Void
    var menu: () -> NSMenu
    var onHover: (Bool) -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.url = url
        view.onDragEnded = onDragEnded
        view.onDoubleClick = onDoubleClick
        view.menuProvider = menu
        view.onHover = onHover
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var url: URL?
        var onDragEnded: ((NSDragOperation) -> Void)?
        var onDoubleClick: (() -> Void)?
        var menuProvider: (() -> NSMenu)?
        var onHover: ((Bool) -> Void)?
        private var mouseDownEvent: NSEvent?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { onHover?(true) }
        override func mouseExited(with event: NSEvent) { onHover?(false) }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            if event.clickCount == 2 { onDoubleClick?() }
        }

        override func mouseDragged(with event: NSEvent) {
            guard let url, let down = mouseDownEvent else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard dx * dx + dy * dy > 9 else { return }
            mouseDownEvent = nil
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 32, height: 32)
            let p = convert(down.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: p.x - 16, y: p.y - 16, width: 32, height: 32), contents: icon)
            beginDraggingSession(with: [item], event: down, source: self)
        }

        override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? .copy : .move
        }

        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            onDragEnded?(operation)
        }
    }
}
