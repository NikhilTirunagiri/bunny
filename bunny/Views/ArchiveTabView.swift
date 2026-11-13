import SwiftUI
import SwiftData

/// Archived notes grouped by day, with Restore and Move to Trash (per row, per selection, or all).
struct ArchiveTabView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var allArchivedTasks: [BunnyTask]

    @State private var expandedIDs: Set<UUID> = []
    @State private var hovered: UUID? = nil
    @State private var selection = ListSelection()

    init() {
        let archived = #Predicate<BunnyTask> { task in task.archivedAt != nil && task.deletedAt == nil }
        _allArchivedTasks = Query(filter: archived, sort: [SortDescriptor(\BunnyTask.archivedAt, order: .reverse)])
    }

    /// Archived top-level notes, plus archived subtasks whose parent is not archived.
    private var archivedParents: [BunnyTask] {
        let archivedParentIDs = Set(allArchivedTasks.filter { $0.parentID == nil }.map { $0.id })
        return allArchivedTasks.filter {
            $0.parentID == nil || $0.parentID.map { !archivedParentIDs.contains($0) } == true
        }
    }

    private func subtasks(of task: BunnyTask) -> [BunnyTask] {
        allArchivedTasks.filter { $0.parentID == task.id }
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var grouped: [(key: String, date: Date, tasks: [BunnyTask])] {
        var dict: [String: (date: Date, tasks: [BunnyTask])] = [:]
        for task in archivedParents {
            guard let archived = task.archivedAt else { continue }
            let key = Self.dayFormatter.string(from: archived)
            if dict[key] == nil {
                dict[key] = (date: archived, tasks: [])
            }
            dict[key]!.tasks.append(task)
        }
        return dict
            .map { (key: $0.key, date: $0.value.date, tasks: $0.value.tasks) }
            .sorted { $0.date > $1.date }
    }

    /// Selectable rows in display order.
    private var visibleIDs: [UUID] { grouped.flatMap { $0.tasks.map(\.id) } }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if archivedParents.isEmpty {
                    ArchiveEmptyState(systemImage: "archivebox", text: "No archived notes")
                } else {
                    archiveList
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
            let count = archivedParents.count
            ArchiveBottomBar(caption: count == 1 ? "1 note" : "\(count) notes") {
                Button("Move All to Trash") {
                    TaskActions.moveToTrash(Set(allArchivedTasks.map(\.id)), in: modelContext)
                }
                .disabled(count == 0)
            }
        } else {
            ArchiveBottomBar(caption: "\(selected.count) selected") {
                Button("Restore") { restore(selected) }
                Button("Move to Trash") { moveToTrash(selected) }
            }
        }
    }

    private var archiveList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(grouped, id: \.key) { group in
                    Section {
                        ForEach(group.tasks) { task in
                            let subs = subtasks(of: task)
                            let isExpanded = expandedIDs.contains(task.id)

                            parentRow(task: task, subs: subs, isExpanded: isExpanded)

                            if isExpanded {
                                ForEach(subs) { sub in
                                    subtaskRow(sub)
                                }
                            }
                        }
                    } header: {
                        Text(group.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.top, 10)
                            .padding(.bottom, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            // Same inset as the notes list and the New note field.
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func parentRow(task: BunnyTask, subs: [BunnyTask], isExpanded: Bool) -> some View {
        let isHovered = hovered == task.id
        return HStack(spacing: 6) {
            Button {
                if isExpanded { expandedIDs.remove(task.id) }
                else { expandedIDs.insert(task.id) }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(subs.isEmpty ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.secondary))
            }
            .buttonStyle(.plain)
            .frame(width: 12)
            .disabled(subs.isEmpty)

            Button { restore([task.id]) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Uncheck to restore")

            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .strikethrough(true, color: .secondary)
                .lineLimit(1)

            Spacer()

            if isHovered {
                Button { restore([task.id]) } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Restore")

                Button { moveToTrash([task.id]) } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Move to Trash")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .appKitContextMenu {
            let targets = selection.targets(for: task.id)
            MenuEntry.item("Restore", image: "arrow.uturn.backward") { restore(targets) }
            MenuEntry.item("Move to Trash", image: "trash", destructive: true) { moveToTrash(targets) }
        }
        .onTapGesture { selection.click(task.id, visible: visibleIDs) }
        .background {
            ConcentricRectangle()
                .fill(archiveRowBackground(selected: selection.ids.contains(task.id), hovered: isHovered))
        }
        .onHover { isHovering in
            hovered = isHovering ? task.id : (hovered == task.id ? nil : hovered)
        }
    }

    private func subtaskRow(_ task: BunnyTask) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
            Text(task.title)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .strikethrough(true, color: Color.secondary.opacity(0.5))
                .lineLimit(1)
            Spacer()
        }
        .padding(.leading, 36)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background {
            ConcentricRectangle()
                .fill(hovered == task.id ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear))
        }
        .onHover { isHovering in
            hovered = isHovering ? task.id : (hovered == task.id ? nil : hovered)
        }
    }

    // Rows that leave the list drop out of the selection via `prune`.
    private func restore(_ ids: Set<UUID>) { TaskActions.restoreFromArchive(ids, in: modelContext) }

    private func moveToTrash(_ ids: Set<UUID>) { TaskActions.moveToTrash(ids, in: modelContext) }
}
