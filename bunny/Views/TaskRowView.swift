import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(TimerManager.self) private var timerManager

    @Bindable var task: BunnyTask
    let hasSubtasks: Bool

    @State private var showTimerPicker = false
    @State private var isEditing = false
    @State private var editTitle = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Expand/collapse arrow (parent tasks only, hidden when no subtasks)
            if !task.isSubtask {
                Button {
                    task.isExpanded.toggle()
                } label: {
                    Image(systemName: task.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(hasSubtasks ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.clear))
                }
                .buttonStyle(.plain)
                .frame(width: 12)
                .disabled(!hasSubtasks)
            }

            // Checkbox
            Button { toggleComplete() } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            // Title — tap once to edit when already selected, double-click otherwise
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($titleFocused)
                    .onSubmit { commitEdit() }
                    .onExitCommand { cancelEdit() }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(task.title)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { startEditing() }
            }

            // Right-side actions
            HStack(spacing: 6) {
                if !task.isSubtask { timerView }

                if !task.isSubtask {
                    Button { addSubtask() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Add subtask")
                }

                if !task.isSubtask {
                    Button { togglePin() } label: {
                        Image(systemName: task.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(task.isPinned ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(task.isPinned ? "Unpin" : "Pin to menu bar")
                }

                Button { archiveTask() } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Move to archive")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onAppear {
            if appState.editingTaskID == task.id {
                appState.editingTaskID = nil
                startEditing()
            }
        }
    }

    @ViewBuilder
    private var timerView: some View {
        let _ = timerManager.tick
        Button {
            showTimerPicker = true
        } label: {
            if task.isTimerRunning {
                Text(task.formattedRemaining)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else if task.isTimerExpired {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Set timer")
        .popover(isPresented: $showTimerPicker, arrowEdge: .bottom) {
            TimerPickerView(task: task)
        }
    }

    // MARK: - Editing

    private func startEditing() {
        editTitle = task.title
        isEditing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            titleFocused = true
        }
    }

    private func commitEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            task.title = trimmed
        } else if task.title.isEmpty {
            ShelfService.removeAll(for: task.id, in: modelContext)
            modelContext.delete(task)
        }
        isEditing = false
    }

    private func cancelEdit() {
        if task.title.isEmpty {
            ShelfService.removeAll(for: task.id, in: modelContext)
            modelContext.delete(task)
        }
        isEditing = false
    }

    // MARK: - Actions

    private func toggleComplete() {
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? Date() : nil
    }

    private func togglePin() {
        if task.isPinned {
            task.isPinned = false
            appState.pinnedTaskID = nil
            appState.timerExpiredTaskID = nil
        } else {
            let descriptor = FetchDescriptor<BunnyTask>(
                predicate: #Predicate { $0.isPinned }
            )
            if let pinned = try? modelContext.fetch(descriptor) {
                for t in pinned { t.isPinned = false }
            }
            task.isPinned = true
            appState.pinnedTaskID = task.id
            appState.timerExpiredTaskID = nil
        }
    }

    private func addSubtask() {
        let sub = BunnyTask(title: "", parentID: task.id)
        modelContext.insert(sub)
        task.isExpanded = true
        appState.editingTaskID = sub.id
    }

    private func archiveTask() {
        task.archivedAt = Date()
        if task.isPinned {
            task.isPinned = false
            appState.pinnedTaskID = nil
            appState.timerExpiredTaskID = nil
        }
        // Archive all subtasks so they don't become orphans
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
