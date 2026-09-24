import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The task currently being dragged from a row, recorded when the drag starts so drop
/// targets can preview the effective zone (the payload itself is only readable on drop).
@MainActor
enum TaskDrag {
    static var currentID: UUID?
    fileprivate static var hint: (dragged: UUID, target: UUID, zone: DropZone, effective: DropZone?)?
}

/// The single drop target on every task row (spec §4): Finder files go to the task's
/// shelf; a dragged task (UUID as plain text) is moved above / below / into this row.
struct RowDropDelegate: DropDelegate {
    let taskID: UUID
    let rowHeight: CGFloat
    let context: ModelContext
    let coordinator: PanelCoordinator
    @Binding var indicator: DropZone?
    @Binding var isFileTargeted: Bool

    private func isFileDrag(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func validateDrop(info: DropInfo) -> Bool {
        isFileDrag(info) || info.hasItemsConforming(to: [.utf8PlainText])
    }

    func dropEntered(info: DropInfo) {
        if isFileDrag(info) {
            isFileTargeted = true
            coordinator.fileDragEntered(taskID)
        } else {
            _ = update(info)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if isFileDrag(info) {
            if !isFileTargeted { isFileTargeted = true }
            return DropProposal(operation: .copy)
        }
        return update(info)
    }

    func dropExited(info: DropInfo) {
        clear()
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { clear() }
        let target = taskID
        let context = context

        // Files first: a Finder drag may also carry plain text, and must never move a task.
        if isFileDrag(info) {
            let providers = info.itemProviders(for: [.fileURL])
            guard !providers.isEmpty else { return false }
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await Self.loadURL(provider) { urls.append(url) }
                }
                ShelfService.add(urls, to: target, in: context)
            }
            return true
        }

        let zone = TaskMoveRules.zone(y: info.location.y, height: max(rowHeight, 1))
        guard let provider = info.itemProviders(for: [.utf8PlainText]).first else { return false }
        TaskDrag.currentID = nil
        Task { @MainActor in
            guard let text = await Self.loadString(provider),
                  let dragged = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  TaskMover.resolvedZone(dragged: dragged, target: target, zone: zone, in: context) != nil
            else { return }
            withAnimation(.snappy(duration: 0.25)) {
                TaskMover.perform(dragged: dragged, target: target, zone: zone, in: context)
            }
        }
        return true
    }

    // MARK: - Helpers

    /// Updates the insertion indicator for a task drag. When the dragged task is known,
    /// the indicator shows the effective zone (into may degrade to below; no-ops show nothing).
    private func update(_ info: DropInfo) -> DropProposal? {
        let zone = TaskMoveRules.zone(y: info.location.y, height: max(rowHeight, 1))
        var effective: DropZone? = zone
        if let dragged = TaskDrag.currentID {
            if let hint = TaskDrag.hint, hint.dragged == dragged, hint.target == taskID, hint.zone == zone {
                effective = hint.effective
            } else {
                effective = TaskMover.resolvedZone(dragged: dragged, target: taskID, zone: zone, in: context)
                TaskDrag.hint = (dragged, taskID, zone, effective)
            }
        }
        if indicator != effective { indicator = effective }
        return DropProposal(operation: effective == nil ? .forbidden : .move)
    }

    private func clear() {
        if indicator != nil { indicator = nil }
        if isFileTargeted { isFileTargeted = false }
        TaskDrag.hint = nil
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadString(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { string, _ in
                continuation.resume(returning: string)
            }
        }
    }
}
