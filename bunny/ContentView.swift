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

    @State private var listHeight: CGFloat = 0

    /// Not in Trash.
    private var liveTasks: [BunnyTask] { allTasks.filter(\.isLive) }

    /// A top-level note and the subtasks listed under it.
    private struct NoteGroup: Identifiable {
        let note: BunnyTask
        let subtasks: [BunnyTask]
        /// The parent shows its chevron and hides the subtasks when folded. Off in search results.
        var foldable = true
        var id: UUID { note.id }

        var showsSubtasks: Bool { !subtasks.isEmpty && (!foldable || note.isExpanded) }
        var ids: [UUID] { [note.id] + (showsSubtasks ? subtasks.map(\.id) : []) }
    }

    /// What the list shows, top to bottom.
    private struct Sections {
        var open: [NoteGroup] = []
        /// Completed top-level notes, most recently completed first. Their subtasks stay with them.
        var completed: [NoteGroup] = []
        /// nil unless a search is typed: the matching notes.
        var results: [NoteGroup]?
    }

    private var sections: Sections {
        let live = liveTasks
        let query = coordinator.searching ? coordinator.searchQuery.trimmingCharacters(in: .whitespaces) : ""
        func matches(_ task: BunnyTask) -> Bool {
            NoteText.matches(query: query, title: task.title, details: task.taskDescription)
        }
        var sections = Sections()
        if !query.isEmpty {
            // A note is listed when it matches or one of its subtasks does; under it, the matching subtasks.
            sections.results = live.filter { !$0.isSubtask }.compactMap { note -> NoteGroup? in
                let subtasks = live.filter { $0.parentID == note.id && matches($0) }
                guard matches(note) || !subtasks.isEmpty else { return nil }
                return NoteGroup(note: note, subtasks: subtasks, foldable: false)
            }
            return sections
        }
        let groups = live.filter { !$0.isSubtask }.map { note in
            NoteGroup(note: note, subtasks: live.filter { $0.parentID == note.id })
        }
        sections.open = groups.filter { !$0.note.isCompleted }
        sections.completed = groups.filter(\.note.isCompleted).sorted {
            ($0.note.completedAt ?? .distantPast) > ($1.note.completedAt ?? .distantPast)
        }
        return sections
    }

    /// Rows in display order (selection and arrow keys): only what is on screen.
    private var visibleIDs: [UUID] {
        let sections = sections
        if let results = sections.results { return results.flatMap(\.ids) }
        return (sections.open + (coordinator.completedExpanded ? sections.completed : [])).flatMap(\.ids)
    }

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.showingTrash {
                TrashView()
            } else {
                NoteFieldView { addNote($0, attachClipboard: $1) }
                taskListView
                selectionStrip
            }
            ListBottomBar()
        }
        .overlay {
            if let confirmation = coordinator.deleteConfirmation {
                DeleteConfirmationView(confirmation: confirmation)
            }
        }
        .containerShape(.rect(cornerRadius: 16))
        .frame(width: 340)
        .onChange(of: visibleIDs, initial: true) { _, ids in
            coordinator.visibleIDs = ids
            // The selection follows what is on screen. The one open note stays open while it is
            // still in the list (e.g. just completed into the folded Completed group).
            let live = Set(liveTasks.map(\.id))
            let openNoteStays = coordinator.selection.single.map(live.contains) ?? false
            coordinator.pruneSelection(keeping: openNoteStays ? live : Set(ids))
        }
    }

    private var taskListView: some View {
        let sections = sections
        return ScrollViewReader { proxy in ScrollView {
            // Rows pad themselves 1 pt above and below (part of their drop target), so the
            // 2 pt gap between groups comes from the rows and subtasks overlap it away (-2).
            LazyVStack(spacing: 0) {
                if let results = sections.results {
                    ForEach(results) { group(for: $0, reorderable: false) }
                } else {
                    ForEach(sections.open) { group(for: $0, reorderable: true) }
                    if !sections.completed.isEmpty {
                        completedHeader(count: sections.completed.count)
                            .id(Self.completedHeaderID)
                        if coordinator.completedExpanded {
                            ForEach(sections.completed) { group(for: $0, reorderable: false) }
                        }
                    }
                }
            }
            // Same inset as the New note field so row highlights line up with it.
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            // A click on empty space (below the rows or beside them) leaves search or clears the
            // selection; rows and their controls take their own clicks first.
            .frame(minHeight: listHeight, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { coordinator.emptySpaceClicked() }
        }
        // Unfolding brings the group into view: below a long list it would open off screen.
        .onChange(of: coordinator.completedExpanded) { _, expanded in
            if expanded { withAnimation { proxy.scrollTo(Self.completedHeaderID, anchor: .top) } }
        }
        }
        // Low enough that a four-line draft and the quick-capture strip still fit the card above it.
        .frame(minHeight: 240)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        .overlay {
            if let results = sections.results {
                if results.isEmpty {
                    emptyState("No matches", "Search looks in titles and details.")
                }
            } else if sections.open.isEmpty && sections.completed.isEmpty {
                emptyState("No notes yet", "Type above and press Return.")
            }
        }
    }

    private static let completedHeaderID = "completed"

    /// "N selected · Complete · Delete" while several notes are selected; otherwise the Undo
    /// offer or a notice. The Space and ⌫ hints are tooltips: inline they would not fit the width.
    private var selectionStrip: some View {
        let ids = coordinator.selection.ids
        return ActionStrip(selected: ids.count > 1 ? ids.count : 0) {
            Button("Complete") { TaskActions.complete(ids, in: modelContext, undoable: true) }
                .help("Complete (Space)")
            Button("Delete") { TaskActions.moveToTrash(ids, in: modelContext, undoable: true) }
                .buttonStyle(.bunnyDestructive)
                .help("Move to Trash (⌫)")
        }
    }

    /// Each row is its own drag source and drop target (TaskRowView / RowDropDelegate);
    /// subtasks keep their parentID, so a collapsed parent moves with them.
    private func group(for group: NoteGroup, reorderable: Bool) -> some View {
        let done = group.subtasks.filter(\.isCompleted).count
        return VStack(spacing: -2) {
            TaskRowView(task: group.note, hasSubtasks: group.foldable && !group.subtasks.isEmpty,
                        progress: group.foldable && !group.subtasks.isEmpty ? "\(done)/\(group.subtasks.count)" : nil,
                        reorderable: reorderable)
            if group.showsSubtasks {
                ForEach(group.subtasks) { sub in
                    TaskRowView(task: sub, hasSubtasks: false, reorderable: reorderable)
                }
            }
        }
    }

    /// "N completed": folds and unfolds the Completed group.
    private func completedHeader(count: Int) -> some View {
        Button { coordinator.toggleCompletedGroup() } label: {
            HStack(spacing: RowMetrics.spacing) {
                Image(systemName: coordinator.completedExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: RowMetrics.checkbox)
                Text("\(count) completed")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.leading, RowMetrics.gutter)
            .padding(.vertical, 7)
        }
        .buttonStyle(.bunnyRow)
        .padding(.top, 6)
    }

    private func emptyState(_ title: String, _ caption: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .allowsHitTesting(false)
    }

    /// Return in the New note field: the note goes to the top of the list (below no other top-level
    /// note's order, so drag-reorder's renumbering keeps it there). Long or multi-line text is split
    /// into title and details. `attachClipboard`: the quick-capture offer was accepted.
    private func addNote(_ text: String, attachClipboard: Bool) {
        let (title, details) = NoteText.split(text)
        guard !title.isEmpty else { return }
        let top = liveTasks.filter { !$0.isSubtask }.map(\.sortOrder).min() ?? 1
        let task = BunnyTask(title: title, sortOrder: top - 1)
        task.taskDescription = details
        modelContext.insert(task)
        if attachClipboard { ShelfService.attachClipboard(to: task.id, in: modelContext) }
    }
}
