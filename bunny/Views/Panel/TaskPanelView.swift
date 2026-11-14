import SwiftUI
import SwiftData

/// The note side. Top to bottom: pin and close (with a subtask's breadcrumb), then one scroll area
/// with the title, the details and the attachments, and a footer that stays put: the created line and
/// Hand off. Files dropped anywhere on it are attached to the note.
struct TaskPanelView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator
    @Query private var matches: [BunnyTask]
    @State private var titleDraft = ""
    @State private var details = DetailsEditor.Handle()
    @State private var scrollHeight: CGFloat = 0
    @State private var isDropTargeted = false
    @FocusState private var titleFocused: Bool
    @AppStorage(PanelCoordinator.pinnedKey) private var pinned = false

    init(taskID: UUID) {
        self.taskID = taskID
        _matches = Query(filter: #Predicate<BunnyTask> { $0.id == taskID })
    }

    /// In Trash or deleted (also by an agent through Bunny tools): the note side closes.
    private var isGone: Bool {
        guard let task = matches.first else { return true }
        return task.deletedAt != nil
    }

    var body: some View {
        Group {
            if let task = matches.first, !isGone {
                content(task)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: isGone, initial: true) { _, gone in
            if gone { coordinator.tasksRemoved([taskID]) }
        }
    }

    private func header(_ task: BunnyTask) -> some View {
        HStack(spacing: 2) {
            if let pid = task.parentID {
                ParentBreadcrumb(parentID: pid)
            }
            Spacer(minLength: 8)
            Button { pinned.toggle() } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(pinned ? Color.accentColor : .secondary)
            }
            .buttonStyle(Self.headerButton)
            .help(pinned ? "Unpin: close the note side on a second click or Esc" : "Pin: keep the note side open")
            Button { coordinator.closeNoteSide() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(Self.headerButton)
            .help("Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
    }

    private static let headerButton = BunnyButtonStyle(kind: .icon(24))

    private func content(_ task: BunnyTask) -> some View {
        VStack(spacing: 0) {
            header(task)
            ScrollView {
                scrollContent(task)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .frame(minHeight: scrollHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
            NoteFooter(task: task)
        }
        // One drop target for the whole note side.
        .dropDestination(for: URL.self) { urls, _ in
            ShelfService.add(urls, to: taskID, in: modelContext) > 0
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.07))
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    .padding(5)
                    .allowsHitTesting(false)
            }
        }
        .onDisappear {
            // Switching task (new `.id`) or deleting tears this view down without a focus change:
            // keep an in-progress title. Skip deleted models: reading a deleted model's attributes can trap.
            if task.modelContext != nil, !task.isDeleted, titleDraft != task.title { commitTitle(task) }
        }
    }

    /// Title, details, attachments. A question from the agent comes first; any other agent state
    /// sits below the attachments. The space between the details and the attachments is part of the
    /// writing area: a click there starts typing.
    @ViewBuilder
    private func scrollContent(_ task: BunnyTask) -> some View {
        @Bindable var task = task
        let needsInput = task.runState == .needsInput && !task.isSubtask
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $titleDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                // Three lines show. The limit is 4 because SwiftUI caps the height at 18 pt a line and
                // AppKit lays this font out at 19: under a cap of 3 the third line does not fit and is
                // not drawn.
                .lineLimit(1...4)
                .focused($titleFocused)
                .onSubmit { commitTitle(task) }
                .onAppear { titleDraft = task.title }
                .onChange(of: titleFocused) { _, focused in if !focused { commitTitle(task) } }
                .onChange(of: task.title) { _, new in if !titleFocused { titleDraft = new } }
            PanelMetaLine(task: task)
            if needsInput {
                agentSection(task)
            }
            VStack(spacing: 0) {
                DetailsEditor(text: $task.taskDescription, handle: details) {
                    ShelfService.attachClipboard(to: taskID, in: modelContext)
                }
                Color.clear
                    .frame(minHeight: 20, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { details.focusAtEnd() }
            }
            ShelfView(taskID: task.id)
            if !needsInput {
                agentSection(task)
            }
        }
    }

    /// Agents belong to parent tasks only (spec): subtasks get no agent section. A note that was never
    /// handed off has none either: its Hand off control is in the footer.
    @ViewBuilder
    private func agentSection(_ task: BunnyTask) -> some View {
        if !task.isSubtask, task.runState != .idle || task.agentSessionID != nil {
            AgentPanelSection(task: task)
                // Its summary scrolls on its own (until Phase 4): keep it from stretching into the
                // writing area's spare room.
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func commitTitle(_ task: BunnyTask) {
        let trimmed = titleDraft.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titleDraft = task.title
        } else {
            if task.title != trimmed { task.title = trimmed }
            titleDraft = trimmed
        }
    }
}

/// The note side's footer, below the scroll area: when the note was created, and Hand off for a
/// top-level note that has no session and no active run. The button starts a run at once with the
/// note's agent; the arrow next to it opens the note's agent menu (agent, model, effort).
private struct NoteFooter: View {
    let task: BunnyTask

    var body: some View {
        let harness = AgentSettings.runSettings(for: task).harness
        VStack(alignment: .leading, spacing: 8) {
            Text(NoteText.createdLabel(task.createdAt, now: Date()))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            if !task.isSubtask && AgentConfigMenu.isAvailable(for: task) {
                HStack(spacing: 2) {
                    Button { AgentSupervisor.shared.primaryAction(for: task) } label: {
                        HStack(spacing: 5) {
                            AgentLogo(harness: harness, size: 13)
                            Text("Hand off")
                        }
                    }
                    .buttonStyle(.bunny)
                    .help("Hand this note to \(harness.displayName)")
                    Menu {
                        AgentConfigMenu(task: task)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(BunnyButtonStyle(kind: .icon(24)))
                    .fixedSize()
                    .help("Agent, model and effort for this note")
                    Text(harness.displayName)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 6)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }
}

/// "In <parent>" breadcrumb for subtasks; queries only the parent row.
private struct ParentBreadcrumb: View {
    @Query private var parents: [BunnyTask]

    init(parentID: UUID) {
        _parents = Query(filter: #Predicate<BunnyTask> { $0.id == parentID })
    }

    var body: some View {
        if let parent = parents.first {
            Label(parent.title, systemImage: "arrow.turn.left.up")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// Timer state and subtask progress. Its own view so the 1 s timer tick only re-renders this line.
private struct PanelMetaLine: View {
    let task: BunnyTask
    @Environment(TimerManager.self) private var timerManager
    @Query private var children: [BunnyTask]

    init(task: BunnyTask) {
        self.task = task
        let taskID = task.id
        _children = Query(filter: #Predicate<BunnyTask> { $0.parentID == taskID && $0.deletedAt == nil },
                          sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
    }

    var body: some View {
        let _ = timerManager.tick
        let showsSubtasks = !task.isSubtask && !children.isEmpty
        if task.hasTimer || showsSubtasks {
            HStack(spacing: 10) {
                if task.isTimerRunning {
                    Label("\(task.formattedRemaining) left", systemImage: "timer")
                } else if task.isTimerExpired {
                    Label("Time's up", systemImage: "clock.badge.checkmark")
                } else if let d = task.timerDuration {
                    Label("\(Int(d / 60)) min timer", systemImage: "clock")
                }
                if showsSubtasks {
                    let done = children.filter(\.isCompleted).count
                    Label("\(done)/\(children.count) subtasks", systemImage: "checklist")
                }
            }
            .font(.system(size: 11.5)).foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
    }
}
