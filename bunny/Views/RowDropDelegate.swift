import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The task currently being dragged from a row, recorded when the drag starts so drop
/// targets can preview the effective zone (the payload itself is only readable on drop).
/// Plain-text drops are only accepted while it is set to a live task, so text dragged in from
/// other apps is refused. It is cleared on drop only: `.onDrag` reports no end of a cancelled
/// drag, and `dropExited` also fires when the pointer just moves on to the next row. So a
/// cancelled drag leaves a stale ID until the next drag replaces it; `validateDrop` refuses it
/// once its task is archived or deleted, and a drop always moves the task named by the payload.
@MainActor
enum TaskDrag {
    static var currentID: UUID?
    fileprivate static var hint: (dragged: UUID, target: UUID, zone: DropZone, effective: DropZone?)?

    /// The task exists and isn't archived.
    fileprivate static func isLive(_ id: UUID, in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.id == id && $0.archivedAt == nil })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}

/// The single drop target on every task row (spec §4): Finder files go to the task's
/// shelf; a dragged task (UUID as plain text) is moved above / below / into this row.
struct RowDropDelegate: DropDelegate {
    let taskID: UUID
    let rowHeight: CGFloat
    /// An expanded parent with visible subtasks: its bottom zone appends as the last subtask.
    let expandedWithChildren: Bool
    let context: ModelContext
    let coordinator: PanelCoordinator
    @Binding var indicator: DropZone?
    @Binding var isFileTargeted: Bool

    private func isFileDrag(_ info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func validateDrop(info: DropInfo) -> Bool {
        if isFileDrag(info) { return true }
        guard let dragged = TaskDrag.currentID, info.hasItemsConforming(to: [.utf8PlainText]) else { return false }
        return TaskDrag.isLive(dragged, in: context)
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

        let zone = dropZone(for: info)
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
    private func dropZone(for info: DropInfo) -> DropZone {
        TaskMoveRules.zone(y: info.location.y, height: max(rowHeight, 1),
                           expandedWithChildren: expandedWithChildren)
    }

    private func update(_ info: DropInfo) -> DropProposal? {
        let zone = dropZone(for: info)
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
                // Finder may hand over file-reference URLs (file:///.file/id=…); bookmark the path.
                continuation.resume(returning: url.map { ($0 as NSURL).filePathURL ?? $0 })
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
