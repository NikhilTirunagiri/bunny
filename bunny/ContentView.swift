import SwiftUI
import SwiftData
import AppKit

extension Notification.Name {
    static let bunnyClosePopover = Notification.Name("bunnyClosePopover")
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
    private var allTasks: [BunnyTask]

    @State private var newTaskTitle = ""
    @State private var activeView: ActiveView = .tasks
    @State private var dropTargetID: UUID? = nil

    /// Local ordering for drag-and-drop — updated instantly on drop
    /// to avoid visual flicker while SwiftData re-sorts.
    @State private var orderedTopLevelIDs: [UUID] = []

    @AppStorage("appearance") private var appearance = "system"
    @FocusState private var newTaskFocused: Bool

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

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            contentArea
            Divider()
            bottomBar
        }
        .frame(width: 340)
        .preferredColorScheme(colorScheme)
        .focusable(true)
        .focusEffectDisabled()
        .onKeyPress(keys: [KeyEquivalent("n")], phases: .down) { keyPress in
            guard keyPress.modifiers == .command else { return .ignored }
            newTaskFocused = true
            return .handled
        }
        .onKeyPress(keys: [KeyEquivalent("w")], phases: .down) { keyPress in
            guard keyPress.modifiers == .command else { return .ignored }
            NotificationCenter.default.post(name: .bunnyClosePopover, object: nil)
            return .handled
        }
        .onKeyPress(keys: [.delete], phases: .down) { _ in
            guard AppState.shared.editingTaskID == nil, !newTaskFocused else { return .ignored }
            archiveSelectedTask()
            return .handled
        }
        .onKeyPress(keys: [.space], phases: .down) { _ in
            guard AppState.shared.editingTaskID == nil, !newTaskFocused else { return .ignored }
            toggleSelectedTask()
            return .handled
        }
        .onChange(of: topLevelTasks.count) { _, _ in
            syncOrderIfNeeded()
        }
        .onAppear {
            syncOrderIfNeeded()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        Group {
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
                        .focused($newTaskFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.quinary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                        .onSubmit { addTask() }
                        .onChange(of: newTaskFocused) { _, focused in
                            if focused { AppState.shared.editingTaskID = nil }
                        }
                }
            } else {
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
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
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
    }

    // MARK: - Task List

    private var taskListView: some View {
        Group {
            if topLevelTasks.isEmpty {
                emptyTaskState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(orderedTopLevelIDs, id: \.self) { id in
                            if let task = allActiveTasks.first(where: { $0.id == id }) {
                                let subs = subtasks(of: task)
                                VStack(spacing: 0) {
                                    TaskRowView(task: task, hasSubtasks: !subs.isEmpty)
                                        .background(alignment: .top) {
                                            // Insertion line indicator when a dragged item
                                            // hovers over this row
                                            if dropTargetID == task.id {
                                                Rectangle()
                                                    .fill(Color.accentColor)
                                                    .frame(height: 2)
                                            }
                                        }

                                    if task.isExpanded && !subs.isEmpty {
                                        ForEach(subs) { sub in
                                            TaskRowView(task: sub, hasSubtasks: false)
                                                .padding(.leading, 24)
                                        }
                                    }
                                }
                                .onDrag {
                                    NSItemProvider(object: task.id.uuidString as NSString)
                                }
                                .dropDestination(for: String.self) { items, _ in
                                    guard let idStr = items.first,
                                          let fromID = UUID(uuidString: idStr),
                                          fromID != task.id else { return false }
                                    moveTask(from: fromID, before: task.id)
                                    dropTargetID = nil
                                    return true
                                } isTargeted: { targeted in
                                    dropTargetID = targeted ? task.id : nil
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(minHeight: 360)
                // Tap empty space below tasks to dismiss editing
                .contentShape(Rectangle())
                .onTapGesture {
                    AppState.shared.editingTaskID = nil
                }
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
        .contentShape(Rectangle())
        .onTapGesture {
            AppState.shared.editingTaskID = nil
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 0) {
            Button {
                let next: ActiveView = activeView == .archive ? .tasks : .archive
                if !reduceMotion { withAnimation(.easeInOut(duration: 0.2)) { activeView = next } }
                else { activeView = next }
                AppState.shared.editingTaskID = nil
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
                AppState.shared.editingTaskID = nil
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

    // MARK: - Ordering

    private func syncOrderIfNeeded() {
        let current = topLevelTasks.map(\.id)
        let old = orderedTopLevelIDs
        // Only resync when IDs change (add / remove), not when sortOrder changes
        if Set(current) != Set(old) {
            orderedTopLevelIDs = current
        } else if old.isEmpty && !current.isEmpty {
            orderedTopLevelIDs = current
        }
    }

    /// Reorder instantly via local array, then persist sortOrders.
    private func moveTask(from fromID: UUID, before toID: UUID) {
        guard let fromIdx = orderedTopLevelIDs.firstIndex(of: fromID),
              let toIdx   = orderedTopLevelIDs.firstIndex(of: toID) else { return }

        let targetOffset = toIdx > fromIdx ? toIdx : toIdx
        orderedTopLevelIDs.move(
            fromOffsets: IndexSet(integer: fromIdx),
            toOffset: targetOffset
        )

        // Persist the new order
        for (i, id) in orderedTopLevelIDs.enumerated() {
            if let t = allActiveTasks.first(where: { $0.id == id }) {
                t.sortOrder = i
            }
        }
    }

    // MARK: - Actions

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = BunnyTask(title: title, sortOrder: topLevelTasks.count)
        modelContext.insert(task)
        newTaskTitle = ""
        AppState.shared.editingTaskID = nil
        // Sync ordering after insert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            syncOrderIfNeeded()
        }
    }

    private func archiveSelectedTask() {
        guard let id = AppState.shared.selectedTaskID,
              let task = allActiveTasks.first(where: { $0.id == id }),
              task.archivedAt == nil else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            task.archivedAt = Date()
            if task.isPinned {
                task.isPinned = false
                AppState.shared.pinnedTaskID = nil
                AppState.shared.timerExpiredTaskID = nil
            }
            if !task.isSubtask {
                let parentID = task.id
                let descriptor = FetchDescriptor<BunnyTask>(
                    predicate: #Predicate { $0.parentID == parentID }
                )
                if let subtasks = try? modelContext.fetch(descriptor) {
                    for sub in subtasks { sub.archivedAt = task.archivedAt }
                }
            }
        }
    }

    private func toggleSelectedTask() {
        guard let id = AppState.shared.selectedTaskID,
              let task = allActiveTasks.first(where: { $0.id == id }),
              task.archivedAt == nil else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}
