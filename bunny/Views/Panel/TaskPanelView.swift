import SwiftUI
import SwiftData

struct TaskPanelView: View {
    let taskID: UUID
    @Environment(PanelCoordinator.self) private var coordinator

    var body: some View {
        Text(taskID.uuidString)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { inside in inside ? coordinator.panelEntered() : coordinator.panelExited() }
    }
}
