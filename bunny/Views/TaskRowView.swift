import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(TimerManager.self) private var timerManager
    @Environment(PanelCoordinator.self) private var coordinator

    @Bindable var task: BunnyTask
    let hasSubtasks: Bool

    @Query private var shelfItems: [ShelfItem]

    @State private var showTimerPicker = false
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isFileTargeted = false
    @State private var isHovered = false
    private var dropIndicator: DropZone? {
        coordinator.dropIndicator.flatMap { $0.taskID == task.id ? $0.zone : nil }
    }
    @State private var rowHeight: CGFloat = 0
    @FocusState private var titleFocused: Bool

    init(task: BunnyTask, hasSubtasks: Bool) {
        self.task = task
        self.hasSubtasks = hasSubtasks
        let id = task.id
        _shelfItems = Query(filter: #Predicate<ShelfItem> { $0.taskID == id })
    }

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
                Image(systemName: checkboxSymbol)
                    .font(.system(size: 17))
                    .foregroundStyle(checkboxColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)

            // Title: a click opens the note at once; a double-click renames in place.
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
                HStack(spacing: 4) {
                    titleLabel
                        .onTapGesture { clicked(onTitle: true) }
                    if !task.taskDescription.isEmpty {
                        Image(systemName: "text.alignleft").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    if !shelfItems.isEmpty {
                        HStack(spacing: 1) {
                            Image(systemName: "paperclip")
                            Text("\(shelfItems.count)")
                        }
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                    .opacity(isHovered || task.isPinned || task.hasTimer ? 1 : 0.0)
                }

                if !task.isSubtask {
                    Button { togglePin() } label: {
                        Image(systemName: task.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(task.isPinned ? Color.accentColor : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .help(task.isPinned ? "Unpin" : "Pin to menu bar")
                }

                if !task.isSubtask {
                    AgentButton(task: task)
                }

                Button { archiveTask() } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Move to archive")
                .opacity(isHovered || task.isPinned || task.hasTimer ? 1 : 0.0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        // Inside the hover and tap modifiers, so its overlay view counts as part of the row.
        .appKitContextMenu { contextMenuItems }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture { clicked(onTitle: false) }
        .overlay { dropIndicatorView }
        .background {
            ConcentricRectangle().fill(rowBackground)
        }
        // Drag & drop live on the full-width row: the subtask indent and a 1 pt strip above and
        // below (the list's inter-row gap) are part of the drop target, so there are no dead zones.
        .padding(.leading, task.isSubtask ? 24 : 0)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
        .onDrag {
            TaskDrag.currentID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        } preview: {
            dragPreview
        }
        // One drop target per row (spec §4): files → shelf, tasks → reorder / nest.
        .onDrop(of: [.fileURL, .utf8PlainText], delegate: RowDropDelegate(
            taskID: task.id,
            rowHeight: rowHeight,
            expandedWithChildren: !task.isSubtask && task.isExpanded && hasSubtasks,
            context: modelContext,
            coordinator: coordinator,
            isFileTargeted: $isFileTargeted
        ))
        .onAppear {
            if appState.editingTaskID == task.id {
                appState.editingTaskID = nil
                startEditing()
            }
        }
    }

    private var isSelected: Bool { coordinator.selection.ids.contains(task.id) }

    /// File drop target, then selection (accent tint), then hover.
    private var rowBackground: AnyShapeStyle {
        if isFileTargeted { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        if isSelected { return AnyShapeStyle(Color.accentColor.opacity(0.2)) }
        if isHovered { return AnyShapeStyle(.quaternary.opacity(0.7)) }
        return AnyShapeStyle(.clear)
    }

    // MARK: - Context menu

    /// On a row inside a multi-selection: actions on the whole selection. Otherwise actions on this row;
    /// a right-click never changes the selection.
    @MenuBuilder
    private var contextMenuItems: [MenuEntry] {
        let selection = coordinator.selection.ids
        if selection.count > 1 && selection.contains(task.id) {
            MenuEntry.item("Complete") { TaskActions.complete(selection, in: modelContext) }
            MenuEntry.item("Archive", image: "archivebox") { TaskActions.archive(selection, in: modelContext) }
            MenuEntry.separator
            MenuEntry.item("Delete", image: "trash", destructive: true) {
                TaskActions.moveToTrash(selection, in: modelContext)
            }
        } else {
            MenuEntry.item("Edit Title") { startEditing() }
            if !task.isSubtask {
                MenuEntry.item("Add Subtask") { addSubtask() }
                MenuEntry.item(task.isPinned ? "Remove from Menu Bar" : "Show in Menu Bar") { togglePin() }
                // The picker is a popover on the timer button; open it once the menu has closed.
                MenuEntry.item("Set Timer…") { DispatchQueue.main.async { showTimerPicker = true } }
                if task.agentSessionID == nil && !task.runState.isActive {
                    MenuEntry.item("Hand Off to \(AgentSettings.runSettings(for: task).harness.displayName)") {
                        AgentSupervisor.shared.primaryAction(for: task)
                    }
                }
            }
            MenuEntry.separator
            MenuEntry.item("Archive", image: "archivebox") { archiveTask() }
            MenuEntry.separator
            MenuEntry.item("Delete", image: "trash", destructive: true) {
                TaskActions.moveToTrash([task.id], in: modelContext)
            }
        }
    }

    // MARK: - Drag & drop

    /// Insertion line above/below the row, or an accent outline + indent arrow for "into".
    @ViewBuilder
    private var dropIndicatorView: some View {
        switch dropIndicator {
        case .above:
            VStack {
                Capsule().fill(Color.accentColor).frame(height: 2).offset(y: -1)
                Spacer(minLength: 0)
            }
            .allowsHitTesting(false)
        case .below:
            VStack {
                Spacer(minLength: 0)
                Capsule().fill(Color.accentColor).frame(height: 2).offset(y: 1)
            }
            .allowsHitTesting(false)
        case .into:
            ZStack(alignment: .leading) {
                ConcentricRectangle()
                    .fill(Color.accentColor.opacity(0.08))
                ConcentricRectangle()
                    .stroke(Color.accentColor, lineWidth: 1.5)
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.leading, 2)
            }
            .allowsHitTesting(false)
        case nil:
            EmptyView()
        }
    }

    /// Compact card shown under the pointer while dragging a row.
    private var dragPreview: some View {
        HStack(spacing: 6) {
            Image(systemName: checkboxSymbol)
                .font(.system(size: 14))
                .foregroundStyle(checkboxColor)
            Text(task.title.isEmpty ? "Untitled" : task.title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
            if hasSubtasks {
                Image(systemName: "list.bullet.indent")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 240, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }

    @ViewBuilder
    private var titleLabel: some View {
        switch task.runState {
        case .running:
            ShimmerText(text: task.title, font: .system(size: 14))
        case .needsInput:
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(Color.agentNeedsInput)
                .lineLimit(1)
        default:
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .strikethrough(task.isCompleted, color: .secondary)
                .lineLimit(1)
        }
    }

    private var checkboxSymbol: String {
        switch task.runState {
        case .needsInput: return "questionmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        default:
            if task.isCompleted && task.completedByAgent { return "checkmark.circle.fill" }
            return task.isCompleted ? "checkmark.circle.fill" : "circle"
        }
    }

    private var checkboxColor: Color {
        switch task.runState {
        case .needsInput: return .agentNeedsInput
        case .failed: return .red
        default:
            if task.isCompleted && task.completedByAgent { return .green }
            return task.isCompleted ? .accentColor : .secondary
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
        // The picker takes key; tell the window not to close underneath it.
        .onChange(of: showTimerPicker) { _, shown in coordinator.setTimerPickerShown(shown) }
        .onDisappear { if showTimerPicker { coordinator.setTimerPickerShown(false) } }
    }

    // MARK: - Editing

    /// Single-tap gestures only, so nothing waits to rule out a double-click. Each click of a
    /// double-click arrives here: the first selects (⌘ toggles, shift extends), the second (click
    /// count 2) renames when it lands on the title and is otherwise ignored, so it doesn't toggle
    /// the note closed.
    private func clicked(onTitle: Bool) {
        if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
            if onTitle { startEditing() }
        } else {
            // Leave any text field so the list's keyboard shortcuts apply to the new selection.
            NSApp.keyWindow?.makeFirstResponder(nil)
            coordinator.rowClicked(task.id)
        }
    }

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
            deleteUntitled()
        }
        isEditing = false
    }

    private func cancelEdit() {
        if task.title.isEmpty {
            deleteUntitled()
        }
        isEditing = false
    }

    /// A new note or subtask left without a title is dropped.
    private func deleteUntitled() {
        coordinator.tasksRemoved([task.id])
        AgentSupervisor.shared.taskWillArchiveOrDelete(task.id)
        ShelfService.removeAll(for: task.id, in: modelContext)
        modelContext.delete(task)
    }

    // MARK: - Actions

    private func toggleComplete() {
        TaskActions.setCompleted(task, !task.isCompleted)
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
        TaskActions.archive([task.id], in: modelContext)
    }
}
