import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Layout shared by the list's rows and the New note field, so their columns line up.
enum RowMetrics {
    /// Leading gutter of a row; a parent's disclosure chevron sits in it.
    static let gutter: CGFloat = 14
    /// Width of the checkbox column.
    static let checkbox: CGFloat = 20
    static let spacing: CGFloat = 6
    /// A subtask's checkbox sits under its parent's title.
    static let subtaskIndent: CGFloat = checkbox + spacing
    /// Row highlights (hover, selection, drop target), a little tighter than the field's corners.
    static let highlight = RoundedRectangle(cornerRadius: 8, style: .continuous)
}

/// One note in the list: checkbox, title, quiet badges, and Hand off on hover. Everything else is in
/// the context menu.
struct TaskRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(PanelCoordinator.self) private var coordinator
    #if DEBUG
    @Environment(\.snapshotHoveredID) private var snapshotHoveredID
    #endif

    @Bindable var task: BunnyTask
    /// Shows the disclosure chevron (a parent with subtasks, outside search results).
    let hasSubtasks: Bool
    /// "1/2" on a parent: its done and total subtasks.
    var progress: String? = nil
    /// False in the Completed group and in search results: the row is no drag source and no reorder
    /// target, but still takes file drops.
    var reorderable = true

    @Query private var shelfItems: [ShelfItem]

    @State private var showTimerPicker = false
    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isFileTargeted = false
    @State private var isHoveredNow = false
    private var dropIndicator: DropZone? {
        coordinator.dropIndicator.flatMap { $0.taskID == task.id ? $0.zone : nil }
    }
    @State private var rowHeight: CGFloat = 0
    @FocusState private var titleFocused: Bool

    init(task: BunnyTask, hasSubtasks: Bool, progress: String? = nil, reorderable: Bool = true) {
        self.task = task
        self.hasSubtasks = hasSubtasks
        self.progress = progress
        self.reorderable = reorderable
        let id = task.id
        _shelfItems = Query(filter: #Predicate<ShelfItem> { $0.taskID == id })
    }

    private var isHovered: Bool {
        #if DEBUG
        if snapshotHoveredID == task.id { return true }
        #endif
        return isHoveredNow
    }

    /// Hand off shows on hover only, on an open top-level note with no session and no active run,
    /// while an agent is switched on.
    private var showsHandOff: Bool {
        isHovered && !isEditing && !task.isSubtask && !task.isCompleted
            && task.agentSessionID == nil && !task.runState.isActive && AgentEnablement.shared.anyEnabled
    }

    var body: some View {
        Group {
            if reorderable {
                row.onDrag {
                    TaskDrag.currentID = task.id
                    return NSItemProvider(object: task.id.uuidString as NSString)
                } preview: {
                    dragPreview
                }
            } else {
                row
            }
        }
        // One drop target per row (spec §4): files → attachments, tasks → reorder / nest.
        .onDrop(of: reorderable ? [.fileURL, .utf8PlainText] : [.fileURL], delegate: RowDropDelegate(
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

    private var row: some View {
        HStack(spacing: RowMetrics.spacing) {
            Button { toggleComplete() } label: {
                Image(systemName: checkboxSymbol)
                    .font(.system(size: 17))
                    .foregroundStyle(checkboxColor)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.bunnyRowIcon)

            // Title: a click opens the note at once; a double-click renames in place.
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($titleFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: titleFocused) { _, focused in
                        // Not after Esc, which ends the edit before the field loses focus.
                        if !focused && isEditing { commitEdit() }
                    }
            } else {
                titleLabel
                    .onTapGesture { clicked(onTitle: true) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                badges
            }

            if showsHandOff {
                AgentButton(task: task)
            }
        }
        .padding(.leading, RowMetrics.gutter)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .leading) { disclosure }
        .contentShape(Rectangle())
        // Inside the hover and tap modifiers, so its overlay view counts as part of the row.
        .appKitContextMenu { contextMenuItems }
        .onHover { isHoveredNow = $0 }
        .onTapGesture { clicked(onTitle: false) }
        .overlay { dropIndicatorView }
        .background {
            RowMetrics.highlight.fill(rowBackground)
        }
        // "Set Timer…" from the menu: the picker hangs under the row.
        .popover(isPresented: $showTimerPicker, arrowEdge: .bottom) {
            TimerPickerView(task: task)
        }
        // The picker takes key; tell the window not to close underneath it.
        .onChange(of: showTimerPicker) { _, shown in coordinator.setTimerPickerShown(shown) }
        .onDisappear { if showTimerPicker { coordinator.setTimerPickerShown(false) } }
        // Drag & drop live on the full-width row: the subtask indent and a 1 pt strip above and
        // below (the list's inter-row gap) are part of the drop target, so there are no dead zones.
        .padding(.leading, task.isSubtask ? RowMetrics.subtaskIndent : 0)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }
    }

    /// The chevron of a parent with subtasks, in the row's leading gutter: rows without one keep the
    /// same checkbox column and reserve nothing for it.
    @ViewBuilder
    private var disclosure: some View {
        if hasSubtasks {
            Button {
                task.isExpanded.toggle()
            } label: {
                Image(systemName: task.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(BunnyTheme.secondary)
            }
            // A little wider than the gutter, for a target that is easy to hit.
            .buttonStyle(BunnyButtonStyle(kind: .icon(18)))
            .offset(x: -2)
        }
    }

    /// Quiet state marks at the trailing end. They only inform; changing any of it is in the menu.
    private var badges: some View {
        HStack(spacing: 6) {
            if task.runState == .running {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse)
                    .help("Agent working")
            }
            if task.runState == .replied && !task.isCompleted {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(Color.accentColor)
                    .help("Agent replied")
            }
            if task.isPinned {
                Image(systemName: "pin.fill").help("Shown in the menu bar")
            }
            if !task.taskDescription.isEmpty {
                Image(systemName: "text.alignleft").help("Has details")
            }
            if !shelfItems.isEmpty {
                HStack(spacing: 1) {
                    Image(systemName: "paperclip")
                    Text("\(shelfItems.count)")
                }
                .help(shelfItems.count == 1 ? "1 attachment" : "\(shelfItems.count) attachments")
            }
            if let progress {
                Text(progress).monospacedDigit().help("Subtasks done")
            }
            if task.hasTimer {
                TimerBadge(task: task)
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(BunnyTheme.tertiary)
        .fixedSize()
    }

    private var isSelected: Bool { coordinator.selection.ids.contains(task.id) }

    /// File drop target, then selection (accent tint), then hover.
    private var rowBackground: AnyShapeStyle {
        if isFileTargeted { return AnyShapeStyle(Color.accentColor.opacity(0.12)) }
        if isSelected { return AnyShapeStyle(BunnyTheme.selection(dark: 0.2)) }
        if isHovered { return AnyShapeStyle(BunnyTheme.surface(dark: .quaternary.opacity(0.7))) }
        return AnyShapeStyle(.clear)
    }

    // MARK: - Context menu

    /// On a row inside a multi-selection: actions on the whole selection. Otherwise actions on this row;
    /// a right-click never changes the selection.
    @MenuBuilder
    private var contextMenuItems: [MenuEntry] {
        let selection = coordinator.selection.ids
        if selection.count > 1 && selection.contains(task.id) {
            MenuEntry.item("Complete") { TaskActions.complete(selection, in: modelContext, undoable: true) }
            MenuEntry.item("Copy as Prompt") { TaskActions.copyAsPrompt(selection, in: modelContext) }
            MenuEntry.separator
            MenuEntry.item("Delete", image: "trash", destructive: true) {
                TaskActions.moveToTrash(selection, in: modelContext, undoable: true)
            }
        } else {
            if !task.isSubtask {
                MenuEntry.item(task.isPinned ? "Remove from Menu Bar" : "Show in Menu Bar",
                               image: task.isPinned ? "pin.slash" : "pin") { togglePin() }
                MenuEntry.separator
            }
            MenuEntry.item("Edit Title") { startEditing() }
            if !task.isSubtask {
                MenuEntry.item("Add Subtask") { addSubtask() }
                // The picker is a popover on the row; open it once the menu has closed.
                MenuEntry.item("Set Timer…") { DispatchQueue.main.async { showTimerPicker = true } }
                if AgentEnablement.shared.anyEnabled && !task.runState.isActive {
                    if task.agentSessionID == nil {
                        MenuEntry.item("Hand Off to \(AgentSettings.runSettings(for: task).harness.displayName)") {
                            AgentSupervisor.shared.primaryAction(for: task)
                        }
                    }
                    MenuEntry.item("Hand Off Options…") { coordinator.openHandOffCard(task.id) }
                }
            }
            MenuEntry.item("Copy as Prompt") { TaskActions.copyAsPrompt([task.id], in: modelContext) }
            MenuEntry.separator
            MenuEntry.item("Delete", image: "trash", destructive: true) {
                TaskActions.moveToTrash([task.id], in: modelContext, undoable: true)
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
                RowMetrics.highlight
                    .fill(Color.accentColor.opacity(0.08))
                RowMetrics.highlight
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
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
                    .foregroundStyle(BunnyTheme.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 240, alignment: .leading)
        .background(BunnyTheme.background(), in: .rect(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }

    /// Working: accent with the shimmer. Needs input: yellow. Completed: dimmed and struck through.
    @ViewBuilder
    private var titleLabel: some View {
        switch task.runState {
        case .running:
            ShimmerText(text: task.title, font: .system(size: 14), color: .accentColor)
        case .needsInput:
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(Color.agentNeedsInput)
                .lineLimit(1)
        default:
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(task.isCompleted ? AnyShapeStyle(BunnyTheme.secondary) : AnyShapeStyle(.primary))
                .strikethrough(task.isCompleted, color: .secondary)
                .lineLimit(1)
        }
    }

    /// Open: empty circle. Done: a tick, blue by the user, green by an agent. Agent waiting: "?".
    /// Agent failed: "!".
    private var checkboxSymbol: String {
        switch task.runState {
        case .needsInput: return "questionmark.circle.fill"
        case .failed: return "exclamationmark.circle.fill"
        default: return task.isCompleted ? "checkmark.circle.fill" : "circle"
        }
    }

    private var checkboxColor: AnyShapeStyle {
        switch task.runState {
        case .needsInput: return AnyShapeStyle(Color.agentNeedsInput)
        case .failed: return AnyShapeStyle(Color.red)
        default:
            guard task.isCompleted else { return AnyShapeStyle(Color.secondary) }
            return task.completedByAgent ? AnyShapeStyle(Color.green) : AnyShapeStyle(BunnyTheme.done)
        }
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
        coordinator.renaming = (task.id, { cancelEdit() })
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
        endEditing()
    }

    /// Esc: the title stays as it was.
    private func cancelEdit() {
        if task.title.isEmpty {
            deleteUntitled()
        }
        endEditing()
    }

    private func endEditing() {
        isEditing = false
        // Another row may have started its rename already (this one ends when it loses focus).
        if coordinator.renaming?.id == task.id { coordinator.renaming = nil }
    }

    /// A new note or subtask left without a title is dropped.
    private func deleteUntitled() {
        coordinator.tasksRemoved([task.id])
        AgentSupervisor.shared.taskWillBeDeleted(task.id)
        ShelfService.removeAll(for: task.id, in: modelContext)
        modelContext.delete(task)
    }

    // MARK: - Actions

    private func toggleComplete() {
        TaskActions.toggleComplete([task.id], in: modelContext, undoable: true)
    }

    private func togglePin() {
        if task.isPinned { TaskActions.unpin(task) } else { TaskActions.pin(task) }
    }

    private func addSubtask() {
        let sub = BunnyTask(title: "", parentID: task.id)
        modelContext.insert(sub)
        task.isExpanded = true
        appState.editingTaskID = sub.id
    }
}

/// The timer mark of a row: the countdown while it runs (or waits to start), a green mark once it
/// ran out. Its own view so the one-second tick redraws this text and not the row.
private struct TimerBadge: View {
    let task: BunnyTask
    @Environment(TimerManager.self) private var timerManager

    var body: some View {
        let _ = timerManager.tick
        if task.isTimerExpired {
            Image(systemName: "clock.badge.checkmark")
                .foregroundStyle(.green)
                .help("Timer finished")
        } else {
            Text(task.formattedRemaining)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(task.isTimerRunning ? AnyShapeStyle(BunnyTheme.secondary) : AnyShapeStyle(BunnyTheme.tertiary))
                .help(task.isTimerRunning ? "Timer running" : "Timer set")
        }
    }
}
