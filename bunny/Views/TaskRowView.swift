import SwiftUI
import SwiftData

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(TimerManager.self) private var timerManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Bindable var task: BunnyTask
    let hasSubtasks: Bool

    @State private var showTimerPicker = false
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isHovering = false
    @State private var showDeleteConfirm = false
    @FocusState private var titleFocused: Bool

    /// Placeholder text to keep the layout stable when editing.
    private var displayTitle: String {
        task.title.isEmpty ? " " : task.title
    }

    var body: some View {
        HStack(spacing: 6) {
            // Expand/collapse arrow (parent tasks only, hidden when no subtasks)
            if !task.isSubtask {
                Button {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
                        task.isExpanded.toggle()
                    }
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
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6)) {
                    toggleComplete()
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(task.isCompleted ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "Mark incomplete" : "Mark complete")

            // Title — single click enters edit mode with cursor at end
            if isEditing {
                TextField("Task title", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($titleFocused)
                    .onSubmit { commitEdit() }
                    .onExitCommand { cancelEdit() }
                    .onChange(of: titleFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
                    .accessibilityLabel("Edit task title")
                    // Prevent parent tap gestures (e.g. ScrollView) from firing
                    // when tapping inside the text field for cursor positioning
                    .onTapGesture { /* consumed here — cursor handled by AppKit */ }
            } else {
                Text(displayTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 1) { startEditing() }
            }

            // Right-side actions — fade in on hover
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
                    .accessibilityLabel("Add subtask")
                }

                if !task.isSubtask {
                    Button { togglePin() } label: {
                        Image(systemName: task.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(task.isPinned ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(task.isPinned ? "Unpin" : "Pin to menu bar")
                    .accessibilityLabel(task.isPinned ? "Unpin from menu bar" : "Pin to menu bar")
                }

                Button { archiveTask() } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Archive task")
                .accessibilityLabel("Archive task")

                // Delete button (permanent)
                if showDeleteConfirm {
                    Button(role: .destructive) { deleteTask() } label: {
                        Text("Delete?")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Confirm permanent delete")
                } else {
                    Button { showDeleteConfirm = true } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Delete permanently")
                    .accessibilityLabel("Delete task permanently")
                }
            }
            .opacity(isHovering ? 1 : 0.4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovering)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(
            isHovering ? Color.primary.opacity(0.04) : Color.clear
        )
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                appState.selectedTaskID = task.id
            } else if appState.selectedTaskID == task.id {
                appState.selectedTaskID = nil
            }
            // Hide delete confirmation when mouse leaves
            if !hovering { showDeleteConfirm = false }
        }
        .onAppear {
            if appState.editingTaskID == task.id {
                appState.editingTaskID = nil
                startEditing()
            }
        }
        // Dismiss editing when another task starts editing
        .onChange(of: appState.editingTaskID) { _, newID in
            if isEditing && newID != task.id {
                commitEdit()
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
        .accessibilityLabel(task.isTimerRunning ? "Timer \(task.formattedRemaining)" : "Set timer")
        .popover(isPresented: $showTimerPicker, arrowEdge: .bottom) {
            TimerPickerView(task: task)
        }
    }

    // MARK: - Editing

    private func startEditing() {
        guard !isEditing else { return }
        editTitle = task.title
        isEditing = true
        appState.editingTaskID = task.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.titleFocused = true
            // Position cursor at end of text instead of selecting all
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let textView = NSApp.keyWindow?.firstResponder as? NSTextView {
                    let length = textView.string.count
                    textView.selectedRange = NSRange(location: length, length: 0)
                }
            }
        }
    }

    private func commitEdit() {
        guard isEditing else { return }
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            task.title = trimmed
        } else if task.title.isEmpty {
            modelContext.delete(task)
        }
        isEditing = false
        appState.editingTaskID = nil
    }

    private func cancelEdit() {
        guard isEditing else { return }
        if task.title.isEmpty {
            modelContext.delete(task)
        }
        isEditing = false
        appState.editingTaskID = nil
    }

    // MARK: - Actions

    private func toggleComplete() {
        commitEdit() // Commit any in-progress edit before acting
        withAnimation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6)) {
            task.isCompleted.toggle()
            task.completedAt = task.isCompleted ? Date() : nil
        }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }

    private func togglePin() {
        commitEdit()
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
        commitEdit()
        let sub = BunnyTask(title: "", parentID: task.id)
        modelContext.insert(sub)
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7)) {
            task.isExpanded = true
        }
        appState.editingTaskID = sub.id
    }

    private func archiveTask() {
        commitEdit()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            task.archivedAt = Date()
            if task.isPinned {
                task.isPinned = false
                appState.pinnedTaskID = nil
                appState.timerExpiredTaskID = nil
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

    private func deleteTask() {
        commitEdit()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) {
            if task.isPinned {
                task.isPinned = false
                appState.pinnedTaskID = nil
                appState.timerExpiredTaskID = nil
            }
            if !task.isSubtask {
                let parentID = task.id
                let descriptor = FetchDescriptor<BunnyTask>(
                    predicate: #Predicate { $0.parentID == parentID }
                )
                if let subtasks = try? modelContext.fetch(descriptor) {
                    for sub in subtasks { modelContext.delete(sub) }
                }
            }
            modelContext.delete(task)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
    }
}
