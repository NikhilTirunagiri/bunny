import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
    private var allTasks: [BunnyTask]

    @State private var newTaskTitle = ""
    @State private var activeView: ActiveView = .tasks
    @State private var dropTargetID: UUID? = nil

    @AppStorage("appearance") private var appearance = "system"

    private enum ActiveView { case tasks, archive, settings }

    private var colorScheme: ColorScheme {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:
            return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        }
    }

    private var allActiveTasks: [BunnyTask] {
        allTasks.filter { $0.archivedAt == nil }
    }

    private var topLevelTasks: [BunnyTask] {
        allActiveTasks.filter { $0.parentID == nil }
    }

    private func subtasks(of task: BunnyTask) -> [BunnyTask] {
        allActiveTasks.filter { $0.parentID == task.id }
    }

    private var currentViewTitle: String {
        switch activeView {
        case .tasks:    return "Tasks"
        case .archive:  return "Archive"
        case .settings: return "Settings"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and input area
            if activeView == .tasks {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "hare.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text(currentViewTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 6)

                    TextField("What's next on your list?", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .onSubmit { addTask() }
                }
            } else {
                // Header for archive/settings
                HStack(spacing: 8) {
                    Image(systemName: activeView == .archive ? "archivebox" : "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text(currentViewTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider()

            // Content area with animated transitions
            ZStack {
                switch activeView {
                case .tasks:
                    taskListView
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity),
                            removal: reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity)
                        ))
                case .archive:
                    ArchiveView()
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity),
                            removal: reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity)
                        ))
                case .settings:
                    SettingsView()
                        .transition(.asymmetric(
                            insertion: reduceMotion ? .identity : .move(edge: .trailing).combined(with: .opacity),
                            removal: reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity)
                        ))
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: activeView)

            Divider()
            bottomBar
        }
        .frame(width: 340)
        .preferredColorScheme(colorScheme)
    }

    private var taskListView: some View {
        Group {
            if topLevelTasks.isEmpty {
                emptyTaskState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(topLevelTasks) { task in
                            let subs = subtasks(of: task)
                            VStack(spacing: 0) {
                                TaskRowView(task: task, hasSubtasks: !subs.isEmpty)

                                if task.isExpanded && !subs.isEmpty {
                                    ForEach(subs) { sub in
                                        TaskRowView(task: sub, hasSubtasks: false)
                                            .padding(.leading, 24)
                                    }
                                }
                            }
                            .background(dropTargetID == task.id ? Color.accentColor.opacity(0.08) : Color.clear)
                            .onDrag {
                                return NSItemProvider(object: task.id.uuidString as NSString)
                            }
                            .dropDestination(for: String.self) { items, _ in
                                guard let idStr = items.first,
                                      let fromID = UUID(uuidString: idStr),
                                      fromID != task.id else { return false }
                                moveTask(from: fromID, to: task.id)
                                dropTargetID = nil
                                return true
                            } isTargeted: { targeted in
                                dropTargetID = targeted ? task.id : nil
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(minHeight: 360)
            }
        }
    }

    private var emptyTaskState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checklist")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No tasks yet")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Text("Type above to add your first task")
                .font(.caption)
                .foregroundStyle(.quaternary)
            Spacer()
        }
        .frame(minHeight: 360)
    }

    private func moveTask(from fromID: UUID, to toID: UUID) {
        var tasks = topLevelTasks
        guard let fromIdx = tasks.firstIndex(where: { $0.id == fromID }),
              let toIdx   = tasks.firstIndex(where: { $0.id == toID }) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            tasks.move(fromOffsets: IndexSet(integer: fromIdx),
                       toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
            for (i, t) in tasks.enumerated() { t.sortOrder = i }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                let next: ActiveView = activeView == .archive ? .tasks : .archive
                if !reduceMotion { withAnimation(.easeInOut(duration: 0.2)) { activeView = next } }
                else { activeView = next }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: activeView == .archive ? "checklist" : "archivebox")
                        .font(.system(size: 13))
                    Text(activeView == .archive ? "Tasks" : "Archive")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(activeView == .archive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .help(activeView == .archive ? "Back to tasks" : "View archived tasks")
            .accessibilityLabel(activeView == .archive ? "Back to tasks" : "View archive")

            Spacer()

            Button {
                let next: ActiveView = activeView == .settings ? .tasks : .settings
                if !reduceMotion { withAnimation(.easeInOut(duration: 0.2)) { activeView = next } }
                else { activeView = next }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text("Settings")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(activeView == .settings ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 16)
            .help(activeView == .settings ? "Back to tasks" : "Open settings")
            .accessibilityLabel(activeView == .settings ? "Back to tasks" : "Open settings")
        }
        .frame(height: 36)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = BunnyTask(title: title, sortOrder: topLevelTasks.count)
        modelContext.insert(task)
        newTaskTitle = ""
    }
}
