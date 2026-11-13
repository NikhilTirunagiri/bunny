import SwiftUI
import SwiftData

/// The main window's content: the glass card with the list, plus the note side on whichever side
/// `WindowPlacement` chose. The window keeps one frame while open; the list is pinned to its edge of the
/// card and the card's width grows over the fixed-width note side to reveal it (and shrinks back),
/// so the list never moves and the note never reflows. Around the card the window is transparent.
/// Appearance comes from `NSApp.appearance` (set by `WindowManager.applyAppearance`), so it follows
/// the theme setting and live system switches.
struct MainWindowView: View {
    @Environment(PanelCoordinator.self) private var coordinator

    private let card = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        let side = coordinator.noteSide
        let edge: Alignment = side == .left ? .trailing : .leading
        let width = WindowPlacement.listWidth + (coordinator.noteSideShown ? WindowPlacement.noteWidth : 0)
        HStack(spacing: 0) {
            if let id = coordinator.displayedNoteID, side == .left {
                noteSide(id, side: side)
            }
            ContentView()
            if let id = coordinator.displayedNoteID, side == .right {
                noteSide(id, side: side)
            }
        }
        // The fixed-width content overflows the card on the note side's edge and is clipped there.
        .frame(width: width, alignment: edge)
        .frame(maxHeight: .infinity)
        .clipShape(card)
        .containerShape(card)
        // Solid for now: glass left a ghost of the card on screen for a moment after closing.
        // (When glass returns it must be a background, never `.glassEffect` on the content: that
        // stops every SwiftUI drop target inside from receiving drags.)
        .background { card.fill(Color(nsColor: .windowBackgroundColor)) }
        .overlay { card.strokeBorder(.separator, lineWidth: 1).allowsHitTesting(false) }
        .background { shadow }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge)
        .padding(.top, WindowPlacement.gap)
        .padding([.horizontal, .bottom], WindowPlacement.shadowMargin)
    }

    /// The card's drop shadow, masked to outside the card: the glass is translucent, so a shadow under
    /// it would darken it.
    private var shadow: some View {
        card.fill(.black)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 5)
            .mask {
                ZStack {
                    Rectangle().padding(-2 * WindowPlacement.shadowMargin)
                    card.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    /// The note plus its divider, at the fixed `WindowPlacement.noteWidth`.
    private func noteSide(_ id: UUID, side: PanelSide) -> some View {
        HStack(spacing: 0) {
            if side == .right { Divider() }
            TaskPanelView(taskID: id)
                .id(id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if side == .left { Divider() }
        }
        .frame(width: WindowPlacement.noteWidth)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PanelCoordinator.self) private var coordinator

    @Query(sort: [SortDescriptor(\BunnyTask.sortOrder), SortDescriptor(\BunnyTask.createdAt)])
    private var allTasks: [BunnyTask]

    @State private var newTaskTitle = ""
    @State private var listHeight: CGFloat = 0
    @FocusState private var newTaskFocused: Bool

    /// Not archived and not in Trash.
    private var allActiveTasks: [BunnyTask] {
        allTasks.filter { $0.archivedAt == nil && $0.deletedAt == nil }
    }

    /// Rows in display order, subtasks of expanded parents included (selection and arrow keys).
    private var visibleIDs: [UUID] {
        topLevelTasks.flatMap { task in
            [task.id] + (task.isExpanded ? subtasks(of: task).map(\.id) : [])
        }
    }

    private var topLevelTasks: [BunnyTask] {
        allActiveTasks.filter { $0.parentID == nil }
    }

    private func subtasks(of task: BunnyTask) -> [BunnyTask] {
        allActiveTasks.filter { $0.parentID == task.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.showingArchive {
                ArchiveView { coordinator.showingArchive = false }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .foregroundStyle(.secondary)
                    TextField("What's next on your list?", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15))
                        .focused($newTaskFocused)
                        .onSubmit { addTask() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 6)

                taskListView
                bottomBar
            }
        }
        .containerShape(.rect(cornerRadius: 16))
        .frame(width: 340)
        // Every open starts on the notes list with focus in the New note field.
        .onChange(of: coordinator.windowOpenCount) { newTaskFocused = true }
        // Async: coming from the Archive view, the field only exists after this update.
        .onChange(of: coordinator.newNoteFocusRequests) { DispatchQueue.main.async { newTaskFocused = true } }
        .onChange(of: newTaskFocused) { _, focused in coordinator.newNoteFieldFocused = focused }
        .onChange(of: visibleIDs, initial: true) { _, ids in
            coordinator.visibleIDs = ids
            coordinator.pruneSelection(keeping: Set(allActiveTasks.map(\.id)))
        }
    }

    private var taskListView: some View {
        ScrollView {
            // Rows pad themselves 1 pt above and below (part of their drop target), so the
            // 2 pt gap between groups comes from the rows and subtasks overlap it away (-2).
            LazyVStack(spacing: 0) {
                ForEach(topLevelTasks) { task in
                    let subs = subtasks(of: task)
                    // Each row is its own drag source and drop target (TaskRowView / RowDropDelegate);
                    // subtasks keep their parentID, so a collapsed parent moves with them.
                    VStack(spacing: -2) {
                        TaskRowView(task: task, hasSubtasks: !subs.isEmpty)
                        if task.isExpanded && !subs.isEmpty {
                            ForEach(subs) { sub in
                                TaskRowView(task: sub, hasSubtasks: false)
                            }
                        }
                    }
                }
            }
            // Same inset as the New note field so row highlights line up with it.
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            // A click on empty space (below the rows or beside them) clears the selection; rows and
            // their controls take their own clicks first.
            .frame(minHeight: listHeight, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { coordinator.emptySpaceClicked() }
        }
        .frame(minHeight: 360)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 8) {
            if coordinator.selection.ids.count > 1 {
                selectionBar
            } else {
                HStack {
                    Button {
                        coordinator.showArchive()
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                    .padding(.leading, 14)
                    .help("Archive and Trash")

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
        }
        .frame(height: 44)
    }

    /// "N selected · Complete · Archive · Delete" while several notes are selected. The Space and ⌫ hints
    /// are tooltips: inline they would not fit the 340 pt list width.
    private var selectionBar: some View {
        let ids = coordinator.selection.ids
        return HStack(spacing: 6) {
            Text("\(ids.count) selected")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Complete") { TaskActions.complete(ids, in: modelContext) }
                .help("Complete (Space)")
            Button("Archive") { TaskActions.archive(ids, in: modelContext) }
            Button("Delete", role: .destructive) { TaskActions.moveToTrash(ids, in: modelContext) }
                .tint(.red)
                .help("Move to Trash (⌫)")
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 14)
    }

    private func addTask() {
        let title = newTaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let task = BunnyTask(title: title, sortOrder: topLevelTasks.count)
        modelContext.insert(task)
        newTaskTitle = ""
    }
}
