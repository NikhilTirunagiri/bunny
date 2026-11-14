import SwiftUI
import SwiftData

/// The note side. Top to bottom: pin and close (with a subtask's breadcrumb), then one scroll area
/// with the title, the details and the attachments, and a footer that stays put: the created line and
/// Hand off. Files dropped anywhere on it are attached to the note.
///
/// A note that was handed off shows either the note or the agent in full (v3 spec §7 "Note/agent
/// fold"). Agent open: the note folds to a small block under the title, the agent part fills the
/// scroll area and the message field is pinned under it. Note open: the agent folds to one status
/// row above the footer. Which one is open is kept per note in `AgentPanelState`.
struct TaskPanelView: View {
    let taskID: UUID
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var matches: [BunnyTask]
    private let agentState = AgentPanelState.shared
    @State private var titleDraft = ""
    @State private var details = DetailsEditor.Handle()
    @State private var scrollHeight: CGFloat = 0
    @State private var isDropTargeted = false
    @State private var footerHeight: CGFloat = 0
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
                    .foregroundStyle(BunnyTheme.secondary)
            }
            .buttonStyle(Self.headerButton)
            .help("Close")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.top, 8)
    }

    private static let headerButton = BunnyButtonStyle(kind: .icon(24))

    // MARK: - Note / agent fold

    /// The agent part is the open one. Until the note side has shown the note, the default.
    private func agentOpen(_ task: BunnyTask) -> Bool {
        task.hasAgentPart && (agentState.agentOpen[task.id] ?? Self.opensAgentByDefault(task))
    }

    private static func opensAgentByDefault(_ task: BunnyTask) -> Bool {
        AgentPanelRules.opensAgent(state: task.runState, lastAgentMessage: task.lastAgentMessageAt, lastSeen: task.agentSeenAt)
    }

    private func setAgentOpen(_ open: Bool, _ task: BunnyTask) {
        guard agentOpen(task) != open else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { agentState.agentOpen[task.id] = open }
    }

    /// The note is being shown (it was opened, or the window reopened on it): pick the default part.
    private func noteShown(_ task: BunnyTask) {
        guard task.hasAgentPart else { return }
        agentState.agentOpen[task.id] = Self.opensAgentByDefault(task)
        markSeen(task)
    }

    /// What the agent said is on screen: no longer unread.
    private func markSeen(_ task: BunnyTask) {
        guard coordinator.windowShown, agentOpen(task), let said = task.lastAgentMessageAt,
              task.agentSeenAt.map({ said > $0 }) ?? true else { return }
        task.agentSeenAt = Date()
    }

    private func content(_ task: BunnyTask) -> some View {
        let agentOpen = agentOpen(task)
        return VStack(spacing: 0) {
            header(task)
            ScrollView {
                scrollContent(task, agentOpen: agentOpen)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .frame(minHeight: scrollHeight, alignment: .top)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
            if agentOpen {
                if AgentMessageField.isAvailable(for: task) {
                    AgentMessageField(task: task)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            } else if task.hasAgentPart {
                foldedAgent(task)
            }
            NoteFooter(task: task)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .onAppear { noteShown(task) }
        .onChange(of: coordinator.windowOpenCount) { noteShown(task) }
        .onChange(of: task.runState) { old, new in
            // A question opens the agent part by itself, and so does a run that starts. A run that
            // ends leaves the view as it is (the folded row shows the new state).
            if new == .needsInput || (new == .running && !old.isActive) { setAgentOpen(true, task) }
        }
        .onChange(of: agentOpen) { markSeen(task) }
        .onChange(of: task.lastAgentMessageAt) { markSeen(task) }
        .overlay(alignment: .bottom) {
            if coordinator.handOffCardTaskID == task.id {
                handOffCard(task)
            }
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

    /// The options card above the footer, over a catcher that closes it on a click anywhere else in
    /// the note side above the footer. The footer stays live under the open card: its Hand off starts
    /// the run with the card's choices (a catcher over it would swallow that click and only close the card).
    private func handOffCard(_ task: BunnyTask) -> some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { coordinator.handOffCardTaskID = nil }
                .padding(.bottom, footerHeight)
            HandOffCard(task: task)
                .padding(.horizontal, 12)
                .padding(.bottom, footerHeight - 4)
        }
    }

    /// The agent part folded to one row above the footer; a click opens it.
    private func foldedAgent(_ task: BunnyTask) -> some View {
        Button { setAgentOpen(true, task) } label: {
            HStack(spacing: 8) {
                AgentStatusLine(task: task)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BunnyTheme.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
        .help("Show the agent")
    }

    /// Title, then the open part. Note open: details and attachments; the space between them is part
    /// of the writing area: a click there starts typing. Agent open: the folded note and the agent.
    @ViewBuilder
    private func scrollContent(_ task: BunnyTask, agentOpen: Bool) -> some View {
        @Bindable var task = task
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
            if agentOpen {
                FoldedNote(task: task) { setAgentOpen(false, task) }
                AgentPanelSection(task: task)
            } else {
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
            }
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

/// The note folded under the title while the agent part is open: the first two lines of the details,
/// how many attachments, and a chevron. A click opens the note.
private struct FoldedNote: View {
    let task: BunnyTask
    let open: () -> Void
    @Query private var shelfItems: [ShelfItem]

    init(task: BunnyTask, open: @escaping () -> Void) {
        self.task = task
        self.open = open
        let taskID = task.id
        _shelfItems = Query(filter: #Predicate<ShelfItem> { $0.taskID == taskID })
    }

    var body: some View {
        let details = task.taskDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        Button(action: open) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(details.isEmpty ? "No details" : details)
                        .font(.system(size: 12.5))
                        .foregroundStyle(details.isEmpty ? AnyShapeStyle(BunnyTheme.tertiary) : AnyShapeStyle(BunnyTheme.secondary))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !shelfItems.isEmpty {
                        Label("\(shelfItems.count)", systemImage: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(BunnyTheme.secondary)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BunnyTheme.secondary)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(BunnyTheme.surface(dark: .quaternary.opacity(0.5)), in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Show the note")
    }
}

/// The note side's footer, below the scroll area: when the note was created, and Hand off for a
/// top-level note while an agent is switched on and no run is active ("Hand off again" once the note
/// has agent state: it replaces the old session). The button starts a run at once with the note's
/// agent and folder; the arrow opens the options card; the caption says which agent and folder.
private struct NoteFooter: View {
    let task: BunnyTask
    @Environment(PanelCoordinator.self) private var coordinator
    @Query private var shelfItems: [ShelfItem]
    private let enablement = AgentEnablement.shared

    init(task: BunnyTask) {
        self.task = task
        let taskID = task.id
        _shelfItems = Query(filter: #Predicate<ShelfItem> { $0.taskID == taskID }, sort: \ShelfItem.sortOrder)
    }

    private var showsHandOff: Bool {
        !task.isSubtask && enablement.anyEnabled && AgentPanelRules.canHandOff(state: task.runState)
    }
    private var handsOffAgain: Bool { task.runState != .idle || task.agentSessionID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NoteText.createdLabel(task.createdAt, now: Date()))
                .font(.system(size: 11.5))
                .foregroundStyle(BunnyTheme.tertiary)
            if showsHandOff {
                handOff
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    private var handOff: some View {
        let harness = AgentSettings.runSettings(for: task, newRun: true).harness
        let folder = AgentSettings.folder(choice: task.agentFolderChoice, shelf: AgentSettings.shelfEntries(shelfItems),
                                          harness: harness)
        let cardOpen = coordinator.handOffCardTaskID == task.id
        return HStack(spacing: 2) {
            Button {
                coordinator.handOffCardTaskID = nil
                AgentSupervisor.shared.start(task, harness: nil)
            } label: {
                HStack(spacing: 5) {
                    AgentLogo(harness: harness, size: 13)
                    Text(handsOffAgain ? "Hand off again" : "Hand off")
                }
            }
            .buttonStyle(.bunny.lively())
            .help("Hand this note to \(harness.displayName)")
            Button {
                coordinator.handOffCardTaskID = cardOpen ? nil : task.id
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(BunnyTheme.secondary)
            }
            .buttonStyle(BunnyButtonStyle(kind: .icon(24), selected: cardOpen))
            .help("Folder, agent, model and effort for this note")
            // "Claude Code · Bunny folder", or only the folder when "Hand off again" leaves no room.
            let folderName = WorkingDirectoryResolver.name(of: folder)
            ViewThatFits(in: .horizontal) {
                Text("\(harness.displayName) · \(folderName)")
                Text(folderName)
                    .truncationMode(.middle)
            }
            .font(.system(size: 11.5))
            .foregroundStyle(BunnyTheme.secondary)
            .lineLimit(1)
            .padding(.leading, 6)
            .help("\(harness.displayName) · \(folder.cwd)")
        }
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
                .font(.system(size: 11.5)).foregroundStyle(BunnyTheme.secondary).lineLimit(1)
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
            .font(.system(size: 11.5)).foregroundStyle(BunnyTheme.secondary)
            .labelStyle(.titleAndIcon)
        }
    }
}
