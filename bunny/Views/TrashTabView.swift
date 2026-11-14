import SwiftUI
import SwiftData

/// Replaces the notes list: a slim header with a back button and the title, then the notes in Trash,
/// most recently deleted first, with days left before the automatic purge. Subtasks travel with
/// their parent and are not listed. The selection lives in `PanelCoordinator` (`trashSelection`), so
/// the window's keys reach it: ↑/↓, ⌘A, ⌫, Esc.
struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator

    @Query(filter: #Predicate<BunnyTask> { $0.deletedAt != nil },
           sort: [SortDescriptor(\BunnyTask.deletedAt, order: .reverse)])
    private var trashed: [BunnyTask]

    @State private var hovered: UUID? = nil

    /// Trashed top-level notes, plus trashed subtasks whose parent is not in Trash.
    private var roots: [BunnyTask] {
        let trashedIDs = Set(trashed.map(\.id))
        return trashed.filter { $0.parentID.map { !trashedIDs.contains($0) } ?? true }
    }

    private var visibleIDs: [UUID] { roots.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if roots.isEmpty {
                    emptyState
                } else {
                    trashList
                }
            }
            .frame(maxHeight: .infinity)
            actionStrip
        }
        .onChange(of: visibleIDs, initial: true) { _, ids in
            coordinator.trashVisibleIDs = ids
            // Rows that left the Trash drop out of the selection.
            let gone = coordinator.trashSelection.ids.subtracting(ids)
            if !gone.isEmpty { coordinator.applyToTrash(.removed(gone)) }
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            Button { coordinator.leaveTrash() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.bunnyIcon)
            .help("Back to notes (Esc)")

            Text("Trash")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
        }
        // The chevron sits in the checkbox column, the title in the rows' title column.
        .padding(.leading, 20)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "trash")
                .font(.system(size: 28))
            Text("Trash is empty")
                .font(.callout)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionStrip: some View {
        let selected = coordinator.trashSelection.ids
        let standing = NotesPreferences.trashRetentionDays.map { "Deleted after \($0) days" }
            ?? "Kept until you delete them"
        return ActionStrip(selected: selected.count, standing: standing) {
            Button("Restore") { TaskActions.restoreFromTrash(selected, in: modelContext) }
            Button("Delete Forever") { TaskActions.confirmDeleteForever(selected, in: modelContext) }
                .buttonStyle(.bunnyDestructive)
                .help("Delete Forever (⌫)")
        } standingActions: {
            Button("Empty Trash") {
                TaskActions.confirmDeleteForever(Set(trashed.map(\.id)), emptying: true, in: modelContext)
            }
            .buttonStyle(.bunnyDestructive)
            .disabled(roots.isEmpty)
        }
    }

    private var trashList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(roots) { task in
                    row(task)
                }
            }
            // Same inset as the notes list and the New note field.
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
    }

    private func row(_ task: BunnyTask) -> some View {
        let selection = coordinator.trashSelection.ids
        return HStack(spacing: RowMetrics.spacing) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(.tertiary)
                .frame(width: RowMetrics.checkbox)
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let retention = NotesPreferences.trashRetentionDays, let deletedAt = task.deletedAt {
                let days = TrashRules.daysLeft(deletedAt: deletedAt, retentionDays: retention, now: Date())
                Text(days == 1 ? "1 day left" : "\(days) days left")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.leading, RowMetrics.gutter)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .appKitContextMenu {
            // On a row inside a multi-selection the menu acts on the selection, otherwise on the row.
            let targets = selection.count > 1 && selection.contains(task.id) ? selection : [task.id]
            MenuEntry.item("Restore", image: "arrow.uturn.backward") { TaskActions.restoreFromTrash(targets, in: modelContext) }
            MenuEntry.item("Delete Forever", image: "trash", destructive: true) {
                TaskActions.confirmDeleteForever(targets, in: modelContext)
            }
        }
        .onTapGesture { coordinator.applyToTrash(PanelCoordinator.clickInput(task.id)) }
        .background {
            RowMetrics.highlight.fill(rowBackground(selected: selection.contains(task.id), hovered: hovered == task.id))
        }
        .onHover { isHovering in
            hovered = isHovering ? task.id : (hovered == task.id ? nil : hovered)
        }
    }

    /// Selection (accent tint), then hover.
    private func rowBackground(selected: Bool, hovered: Bool) -> AnyShapeStyle {
        if selected { return AnyShapeStyle(Color.accentColor.opacity(0.2)) }
        if hovered { return AnyShapeStyle(.quaternary.opacity(0.7)) }
        return AnyShapeStyle(.clear)
    }
}

/// A pending Delete Forever / Empty Trash, shown by `DeleteConfirmationView` over the list column.
struct DeleteConfirmation {
    let title: String
    let confirmTitle: String
    let onConfirm: () -> Void
}

/// The confirmation before Delete Forever / Empty Trash: a scrim and a small card inside the window
/// (an alert would sit under the status-bar-level panel). Cancel is the default; Esc, Return (both via
/// `MainWindowController`) and a click on the scrim cancel. "Do not ask again" is saved only on confirm.
struct DeleteConfirmationView: View {
    let confirmation: DeleteConfirmation
    @Environment(PanelCoordinator.self) private var coordinator
    @State private var doNotAskAgain = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .contentShape(Rectangle())
                .onTapGesture { coordinator.deleteConfirmation = nil }
            VStack(alignment: .leading, spacing: 10) {
                Text(confirmation.title)
                    .font(.system(size: 13, weight: .semibold))
                Text("These notes and their subtasks are removed for good. Attached files stay on disk.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Do not ask again", isOn: $doNotAskAgain)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel") { coordinator.deleteConfirmation = nil }
                        .buttonStyle(.bunny)
                    Button(confirmation.confirmTitle) {
                        if doNotAskAgain { NotesPreferences.confirmDeleteForever = false }
                        coordinator.deleteConfirmation = nil
                        confirmation.onConfirm()
                    }
                    .buttonStyle(.bunnyDestructive)
                }
            }
            .padding(14)
            .frame(width: 260)
            .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
            .shadow(radius: 12)
        }
    }
}
