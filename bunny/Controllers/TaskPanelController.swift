import AppKit
import SwiftUI
import SwiftData

/// Owns the side panel window: creates it, keeps it attached to the popover window, swaps its task.
@MainActor
final class TaskPanelController {
    private let panel: TaskPanel
    private let host: NSHostingView<AnyView>
    private weak var popoverWindow: NSWindow?
    private weak var popoverContentView: NSView?
    private let modelContainer: ModelContainer

    var window: NSWindow { panel }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        host = NSHostingView(rootView: AnyView(EmptyView()))
        // The panel frame comes from PanelPlacement; don't let SwiftUI content resize the window.
        host.sizingOptions = []
        panel = TaskPanel(content: host)
        PanelCoordinator.shared.onShow = { [weak self] id in self?.show(taskID: id) }
        PanelCoordinator.shared.onHide = { [weak self] in self?.hide() }
    }

    func attach(to popoverWindow: NSWindow, contentView: NSView) {
        self.popoverWindow = popoverWindow
        self.popoverContentView = contentView
    }

    func show(taskID: UUID) {
        // Early return leaves HoverIntent's shownTaskID set; harmless, rows are only hoverable while the popover is visible.
        guard let popoverWindow, popoverWindow.isVisible,
              let contentView = popoverContentView, contentView.window === popoverWindow,
              let screen = popoverWindow.screen ?? NSScreen.main else { return }
        host.rootView = AnyView(
            TaskPanelView(taskID: taskID)
                .id(taskID)
                .modelContainer(modelContainer)
                .environment(AppState.shared)
                .environment(TimerManager.shared)
                .environment(PanelCoordinator.shared)
        )
        // Place against the popover's content rect (screen coords), not its window frame (which includes arrow + margins).
        let contentRect = popoverWindow.convertToScreen(contentView.convert(contentView.bounds, to: nil))
        let placement = PanelPlacement.frame(popover: contentRect, visible: screen.visibleFrame)
        panel.setFrame(placement.frame, display: true)
        if panel.parent !== popoverWindow {
            panel.parent?.removeChildWindow(panel)
            popoverWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        if panel.isKeyWindow { popoverWindow?.makeKey() }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
