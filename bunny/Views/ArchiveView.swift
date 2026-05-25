import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(filter: #Predicate<BunnyTask> { $0.archivedAt != nil },
           sort: [SortDescriptor(\BunnyTask.archivedAt, order: .reverse)])
    private var allArchivedTasks: [BunnyTask]

    @State private var expandedIDs: Set<UUID> = []

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

    var body: some View {
        Group {
            if archivedParents.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    // Clear All button at top
                    HStack {
                        Spacer()
                        Button(role: .destructive) { clearAllArchived() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Clear All")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .opacity(0.7)
                        .padding(.trailing, 16)
                        .padding(.top, 6)
                        .help("Delete all archived tasks permanently")
                        .accessibilityLabel("Clear all archived tasks")
                    }

                    archiveList
                }
            }
        }
        .frame(minHeight: 360)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No archived tasks")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("Completed tasks are archived each night")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
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
                                        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    } header: {
                        Text(group.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.regularMaterial)
                            .overlay(alignment: .bottom) {
                                Divider()
                            }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func parentRow(task: BunnyTask, subs: [BunnyTask], isExpanded: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                    if isExpanded { expandedIDs.remove(task.id) }
                    else { expandedIDs.insert(task.id) }
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(subs.isEmpty ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.secondary))
            }
            .buttonStyle(.plain)
            .frame(width: 12)
            .disabled(subs.isEmpty)
            .accessibilityLabel(isExpanded ? "Collapse subtasks" : "Expand subtasks")

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    restore(task, subs: subs)
                }
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Restore task")
            .accessibilityLabel("Restore task")

            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .strikethrough(true, color: .secondary)
                .lineLimit(1)

            Spacer()

            // Delete button for archived task
            Button(role: .destructive) { deleteArchived(task, subs: subs) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Delete permanently")
            .accessibilityLabel("Delete task permanently")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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

            Button(role: .destructive) { deleteArchived(task, subs: []) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete permanently")
            .accessibilityLabel("Delete subtask permanently")
        }
        .padding(.leading, 36)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
    }

    private func restore(_ task: BunnyTask, subs: [BunnyTask]) {
        task.archivedAt = nil
        task.isCompleted = false
        task.completedAt = nil
        if task.isTimerExpired { task.timerStartedAt = nil }
        for sub in subs {
            sub.archivedAt = nil
            sub.isCompleted = false
            sub.completedAt = nil
            if sub.isTimerExpired { sub.timerStartedAt = nil }
        }
    }

    private func deleteArchived(_ task: BunnyTask, subs: [BunnyTask]) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            if !subs.isEmpty {
                for sub in subs {
                    modelContext.delete(sub)
                }
            }
            modelContext.delete(task)
        }
    }

    private func clearAllArchived() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            for task in allArchivedTasks {
                modelContext.delete(task)
            }
        }
    }
}
