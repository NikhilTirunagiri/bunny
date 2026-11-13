import AppKit
import Observation

/// Shared UI state of the main window: the notes-list selection (the note side shows the note when
/// exactly one is selected), and the signals the window controller and the views exchange.
@MainActor
@Observable
final class PanelCoordinator {
    static let shared = PanelCoordinator()
    private init() {}

    static let pinnedKey = "noteSide.pinned"
    /// Pinned: the note side stays open, follows the selection and is restored when the window reopens.
    static var isPinned: Bool { UserDefaults.standard.bool(forKey: pinnedKey) }

    /// Selected notes in the notes list (`SelectionModel`).
    private(set) var selection = SelectionModel.Selection() {
        didSet { if selection.single != oldValue.single { onOpenTaskChange?() } }
    }
    /// The note shown in the note side: the single selected note.
    var openTaskID: UUID? { selection.single }
    /// The note the note side renders: follows `openTaskID`, but the window controller keeps it until
    /// the close animation ends so the note side doesn't empty while it is tucked away.
    var displayedNoteID: UUID?
    /// The card is stretched out to show the note side; the window controller animates the change.
    var noteSideShown = false
    /// The Archive/Trash view replaces the notes list.
    var showingArchive = false
    /// The reorder/nest indicator of the task drag in progress. One for the whole list, so only
    /// one row can ever show it (SwiftUI does not always send `dropExited` to the row left behind).
    var dropIndicator: (taskID: UUID, zone: DropZone)?
    /// Which side of the list the note side sits on; set by the window controller from `WindowPlacement`
    /// each time the window opens.
    var noteSide: PanelSide = .left
    /// The in-window Delete Forever / Empty Trash confirmation while it is up.
    var deleteConfirmation: DeleteConfirmation?
    /// Bumped every time the window opens; the list resets to its default state on change.
    private(set) var windowOpenCount = 0
    /// Bumped by ⌘N; the list focuses the New note field on change.
    private(set) var newNoteFocusRequests = 0

    /// Visible notes-list rows in display order (subtasks of expanded parents included); set by the list.
    @ObservationIgnored var visibleIDs: [UUID] = []
    /// The New note field has focus (Esc then skips the "end text edit" step).
    @ObservationIgnored var newNoteFieldFocused = false
    /// The timer picker popover is showing; the window must not close when it takes key.
    @ObservationIgnored private(set) var timerPickerShown = false

    @ObservationIgnored var onOpenTaskChange: (() -> Void)?
    @ObservationIgnored var onTransientUIEnded: (() -> Void)?

    // MARK: - Selection

    func apply(_ input: SelectionModel.Input) {
        let next = SelectionModel.apply(input, to: selection, visible: visibleIDs)
        if next != selection { selection = next }
    }

    /// A click on a row; ⌘ toggles, shift extends. Clicking the only selected note closes the note
    /// side unless it is pinned.
    func rowClicked(_ id: UUID) {
        let input = Self.clickInput(id)
        if case .click = input, Self.isPinned, selection.ids == [id] { return }
        apply(input)
    }

    /// Plain / ⌘ / shift click, from the current event's modifier flags.
    static func clickInput(_ id: UUID) -> SelectionModel.Input {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) { return .toggle(id) }
        if flags.contains(.shift) { return .extend(id) }
        return .click(id)
    }

    /// A click on empty space in the list clears the selection, except a pinned note side's single note.
    func emptySpaceClicked() {
        if Self.isPinned && selection.single != nil { return }
        apply(.clear)
    }

    func open(_ id: UUID) { apply(.select(id)) }

    /// Shows the last clicked note alone (Return).
    func openCursor() {
        if let cursor = selection.cursor, visibleIDs.contains(cursor) { apply(.select(cursor)) }
    }

    func closeNoteSide() { apply(.clear) }

    /// Notes that were archived, trashed or deleted: drop them from the selection.
    func tasksRemoved(_ ids: [UUID]) { apply(.removed(Set(ids))) }

    /// Drops selected ids that are no longer in the active list (e.g. changed by an agent).
    func pruneSelection(keeping active: Set<UUID>) {
        let gone = selection.ids.subtracting(active)
        if !gone.isEmpty { apply(.removed(gone)) }
    }

    // MARK: - Window signals

    func windowDidOpen() {
        showingArchive = false
        deleteConfirmation = nil
        if !Self.isPinned || selection.single == nil { apply(.clear) }
        windowOpenCount += 1
    }

    /// Shows the Archive/Trash view; the note side closes, pinned or not.
    func showArchive() {
        showingArchive = true
        apply(.clear)
    }

    func focusNewNote() {
        showingArchive = false
        newNoteFocusRequests += 1
    }

    func setTimerPickerShown(_ shown: Bool) {
        guard timerPickerShown != shown else { return }
        timerPickerShown = shown
        if !shown { onTransientUIEnded?() }
    }
}
