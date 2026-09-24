import AppKit
import SwiftUI
import SwiftData

/// Owns the side panel window: creates it, keeps it attached to the popover window, swaps its task.
@MainActor
final class TaskPanelController {
    private let panel: TaskPanel
    private let host: NSHostingView<AnyView>
    private weak var popoverWindow: NSWindow?
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

    func attach(to popoverWindow: NSWindow) {
        self.popoverWindow = popoverWindow
    }

    func show(taskID: UUID) {
        guard let popoverWindow, popoverWindow.isVisible,
              let screen = popoverWindow.screen ?? NSScreen.main else { return }
        host.rootView = AnyView(
            TaskPanelView(taskID: taskID)
                .id(taskID)
                .modelContainer(modelContainer)
                .environment(AppState.shared)
                .environment(TimerManager.shared)
                .environment(PanelCoordinator.shared)
        )
        let placement = PanelPlacement.frame(popover: popoverWindow.frame, visible: screen.visibleFrame)
        panel.setFrame(placement.frame, display: true)
        if panel.parent !== popoverWindow {
            panel.parent?.removeChildWindow(panel)
            popoverWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFront(nil)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }
}
