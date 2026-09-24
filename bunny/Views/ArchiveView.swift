import SwiftUI
import SwiftData

struct ArchiveView: View {
    @Query(sort: [SortDescriptor(\BunnyTask.archivedAt, order: .reverse)])
    private var allArchivedTasks: [BunnyTask]

    @State private var expandedIDs: Set<UUID> = []
    @State private var hovered: UUID? = nil

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
                archiveList
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
                                }
                            }
                        }
                    } header: {
                        Text(group.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.top, 10)
                            .padding(.bottom, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func parentRow(task: BunnyTask, subs: [BunnyTask], isExpanded: Bool) -> some View {
        HStack(spacing: 6) {
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

            Button { restore(task, subs: subs) } label: {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background {
            ConcentricRectangle()
                .fill(hovered == task.id ? AnyShapeStyle(.quaternary.opacity(0.7)) : AnyShapeStyle(.clear))
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

    private func restore(_ task: BunnyTask, subs: [BunnyTask]) {
        // A restored task starts fresh: no stale run state, question or session from before archiving.
        for t in [task] + subs {
            if t.runState.isActive { AgentSupervisor.shared.stop(t) }   // e.g. archived while needsInput
            AgentSupervisor.shared.clear(t)
        }
        task.archivedAt = nil
        task.isCompleted = false
        task.completedAt = nil
        task.completedByAgent = false
        if task.isTimerExpired { task.timerStartedAt = nil }
        for sub in subs {
            sub.archivedAt = nil
            sub.isCompleted = false
            sub.completedAt = nil
            sub.completedByAgent = false
            if sub.isTimerExpired { sub.timerStartedAt = nil }
        }
    }
}
