import SwiftUI
import SwiftData

/// Notes in Trash, most recently deleted first, with days left before the automatic purge.
/// Subtasks travel with their parent and are not listed.
struct TrashTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator

    @Query(filter: #Predicate<BunnyTask> { $0.deletedAt != nil },
           sort: [SortDescriptor(\BunnyTask.deletedAt, order: .reverse)])
    private var trashed: [BunnyTask]

    @State private var hovered: UUID? = nil
    @State private var selection = ListSelection()

    /// Trashed top-level notes, plus trashed subtasks whose parent is not in Trash.
    private var roots: [BunnyTask] {
        let trashedIDs = Set(trashed.map(\.id))
        return trashed.filter { $0.parentID.map { !trashedIDs.contains($0) } ?? true }
    }

    private var visibleIDs: [UUID] { roots.map(\.id) }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if roots.isEmpty {
                    ArchiveEmptyState(systemImage: "trash", text: "Trash is empty")
                } else {
                    trashList
                }
            }
            .frame(maxHeight: .infinity)
            bottomBar
        }
        .onChange(of: visibleIDs) { _, ids in selection.prune(visible: ids) }
    }

    @ViewBuilder
    private var bottomBar: some View {
        let selected = selection.ids
        if selected.isEmpty {
            let caption = NotesPreferences.trashRetentionDays.map { "Deleted after \($0) days" }
                ?? "Kept until you delete them"
            ArchiveBottomBar(caption: caption) {
                Button("Empty Trash", role: .destructive) { deleteForever(Set(trashed.map(\.id)), emptying: true) }
                    .tint(.red)
                    .disabled(roots.isEmpty)
            }
        } else {
            ArchiveBottomBar(caption: "\(selected.count) selected") {
                Button("Restore") { TaskActions.restoreFromTrash(selected, in: modelContext) }
                Button("Delete Forever", role: .destructive) { deleteForever(selected) }
                    .tint(.red)
            }
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
        HStack(spacing: 6) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17))
                .foregroundStyle(.tertiary)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .appKitContextMenu {
            let targets = selection.targets(for: task.id)
            MenuEntry.item("Restore", image: "arrow.uturn.backward") { TaskActions.restoreFromTrash(targets, in: modelContext) }
            MenuEntry.item("Delete Forever", image: "trash", destructive: true) { deleteForever(targets) }
        }
        .onTapGesture { selection.click(task.id, visible: visibleIDs) }
        .background {
            ConcentricRectangle()
                .fill(archiveRowBackground(selected: selection.ids.contains(task.id), hovered: hovered == task.id))
        }
        .onHover { isHovering in
            hovered = isHovering ? task.id : (hovered == task.id ? nil : hovered)
        }
    }

    /// Asks first (in-window, `DeleteConfirmationView`) unless "Do not ask again" was chosen
    /// (`trash.confirmDeleteForever`).
    private func deleteForever(_ ids: Set<UUID>, emptying: Bool = false) {
        guard !ids.isEmpty else { return }
        let context = modelContext
        let delete = { TaskActions.deleteForever(ids, in: context) }
        guard NotesPreferences.confirmDeleteForever else {
            delete()
            return
        }
        coordinator.deleteConfirmation = DeleteConfirmation(
            title: emptying ? "Empty Trash?" : "Delete forever?",
            confirmTitle: emptying ? "Empty Trash" : "Delete Forever",
            onConfirm: delete)
    }
}

/// A pending Delete Forever / Empty Trash, shown by `DeleteConfirmationView` over the Archive view.
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
                        .keyboardShortcut(.defaultAction)
                    Button(confirmation.confirmTitle, role: .destructive) {
                        if doNotAskAgain { NotesPreferences.confirmDeleteForever = false }
                        coordinator.deleteConfirmation = nil
                        confirmation.onConfirm()
                    }
                    .tint(.red)
                }
            }
            .padding(14)
            .frame(width: 260)
            .background(.regularMaterial, in: .rect(cornerRadius: 12, style: .continuous))
            .shadow(radius: 12)
        }
    }
}
