import SwiftUI
import SwiftData

struct TaskPanelView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator
    @Environment(TimerManager.self) private var timerManager
    @Query private var matches: [BunnyTask]
    @Query private var parents: [BunnyTask]
    @Query private var children: [BunnyTask]
    @State private var titleDraft = ""
    @FocusState private var focus: Field?
    private enum Field { case title, description }

    init(taskID: UUID) {
        self.taskID = taskID
        _matches = Query(filter: #Predicate<BunnyTask> { $0.id == taskID })
        _children = Query(filter: #Predicate<BunnyTask> { $0.parentID == taskID && $0.archivedAt == nil },
                          sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
        _parents = Query()
    }

    var body: some View {
        Group {
            if let task = matches.first {
                content(task)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onHover { $0 ? coordinator.panelEntered() : coordinator.panelExited() }
        .onChange(of: focus) { _, f in coordinator.setEditing(f != nil) }
    }

    @ViewBuilder
    private func content(_ task: BunnyTask) -> some View {
        @Bindable var task = task
        VStack(alignment: .leading, spacing: 12) {
            if let pid = task.parentID, let parent = parents.first(where: { $0.id == pid }) {
                Label(parent.title, systemImage: "arrow.turn.left.up")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            TextField("Title", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1...3)
                .focused($focus, equals: .title)
                .onSubmit { commitTitle(task) }
                .onAppear { titleDraft = task.title }
                .onChange(of: focus) { old, _ in if old == .title { commitTitle(task) } }
            metaLine(task)
            ZStack(alignment: .topLeading) {
                if task.taskDescription.isEmpty {
                    Text("Add a description…").font(.system(size: 13)).foregroundStyle(.tertiary)
                        .padding(.top, 1).allowsHitTesting(false)
                }
                TextEditor(text: $task.taskDescription)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .focused($focus, equals: .description)
            }
            .frame(minHeight: 60, maxHeight: 180)
            ShelfView(taskID: task.id)
            Spacer(minLength: 0)
            agentSection(task)
        }
        .padding(16)
    }

    @ViewBuilder
    private func metaLine(_ task: BunnyTask) -> some View {
        let _ = timerManager.tick
        HStack(spacing: 10) {
            if task.isTimerRunning {
                Label("\(task.formattedRemaining) left", systemImage: "timer")
            } else if task.isTimerExpired {
                Label("Time's up", systemImage: "clock.badge.checkmark")
            } else if let d = task.timerDuration {
                Label("\(Int(d / 60)) min timer", systemImage: "clock")
            }
            if !task.isSubtask && !children.isEmpty {
                let done = children.filter(\.isCompleted).count
                Label("\(done)/\(children.count) subtasks", systemImage: "checklist")
            }
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }

    /// Spec B mounts the agent status / questions UI here.
    @ViewBuilder
    private func agentSection(_ task: BunnyTask) -> some View {
        EmptyView()
    }

    private func commitTitle(_ task: BunnyTask) {
        let trimmed = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { titleDraft = task.title } else { task.title = trimmed }
    }
}
