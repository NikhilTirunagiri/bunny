import SwiftUI
import SwiftData
import AppKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
    private var allTasks: [BunnyTask]

    @State private var newTaskTitle = ""
    @State private var activeView: ActiveView = .tasks

    @AppStorage("appearance") private var appearance = "system"

    private enum ActiveView { case tasks, archive }

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
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                    TextField("What's next on your list?", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .onSubmit { addTask() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            switch activeView {
            case .tasks:    taskListView
            case .archive:  ArchiveView()
            }

            bottomBar
        }
        .containerShape(.rect(cornerRadius: 16))
        .frame(width: 340)
        .preferredColorScheme(colorScheme)
    }

    private var taskListView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(topLevelTasks) { task in
                    let subs = subtasks(of: task)
                    // Each row is its own drag source and drop target (TaskRowView / RowDropDelegate);
                    // subtasks keep their parentID, so a collapsed parent moves with them.
                    VStack(spacing: 0) {
                        TaskRowView(task: task, hasSubtasks: !subs.isEmpty)
                        if task.isExpanded && !subs.isEmpty {
                            ForEach(subs) { sub in
                                TaskRowView(task: sub, hasSubtasks: false)
                                    .padding(.leading, 24)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .frame(minHeight: 360)
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            HStack {
                Button {
                    activeView = activeView == .archive ? .tasks : .archive
                } label: {
                    Image(systemName: activeView == .archive ? "checklist" : "archivebox")
                        .font(.system(size: 14))
                        .foregroundStyle(activeView == .archive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(.leading, 14)
                .help(activeView == .archive ? "Back to tasks" : "Archive")

                Spacer()

                Button {
                    WindowManager.shared.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .padding(.trailing, 14)
                .help("Settings")
            }
        }
        .frame(height: 44)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = BunnyTask(title: title, sortOrder: topLevelTasks.count)
        modelContext.insert(task)
        newTaskTitle = ""
    }
}
