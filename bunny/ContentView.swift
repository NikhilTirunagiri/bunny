import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

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

    var body: some View {
        VStack(spacing: 0) {
            if activeView == .tasks {
                TextField("What's next on your list?", text: $newTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onSubmit { addTask() }

                Divider()
            }

            switch activeView {
            case .tasks:    taskListView
            case .archive:  ArchiveView()
            case .settings: SettingsView()
            }

            Divider()
            bottomBar
        }
        .frame(width: 340)
        .preferredColorScheme(colorScheme)
    }

    private var taskListView: some View {
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

    private func moveTask(from fromID: UUID, to toID: UUID) {
        var tasks = topLevelTasks
        guard let fromIdx = tasks.firstIndex(where: { $0.id == fromID }),
              let toIdx   = tasks.firstIndex(where: { $0.id == toID }) else { return }
        tasks.move(fromOffsets: IndexSet(integer: fromIdx),
                   toOffset: toIdx > fromIdx ? toIdx + 1 : toIdx)
        for (i, t) in tasks.enumerated() { t.sortOrder = i }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                activeView = activeView == .archive ? .tasks : .archive
            } label: {
                Image(systemName: activeView == .archive ? "checklist" : "archivebox")
                    .font(.system(size: 14))
                    .foregroundStyle(activeView == .archive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .help(activeView == .archive ? "Back to tasks" : "Archive")

            Spacer()

            Button {
                activeView = activeView == .settings ? .tasks : .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .foregroundStyle(activeView == .settings ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .help(activeView == .settings ? "Back to tasks" : "Settings")
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
