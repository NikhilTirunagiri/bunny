import AppKit
import Observation
import SwiftUI

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
    static let completedExpandedKey = "list.completedExpanded"
    static let undoDuration: TimeInterval = 3
    static let noticeDuration: TimeInterval = 1.5

    /// What the action strip above the bottom bar shows. `restore` nil: a notice only ("Copied 2 notes"), no Undo.
    struct UndoOffer {
        let id = UUID()
        let message: String
        let restore: (() -> Void)?
    }

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
    /// The Trash view replaces the notes list.
    private(set) var showingTrash = false
    /// Selected notes in the Trash view (same rules as the notes list; no note side).
    private(set) var trashSelection = SelectionModel.Selection()
    /// The New note field is a search field, and what is typed in it.
    private(set) var searching = false
    var searchQuery = ""
    /// The Completed group at the bottom of the list is unfolded (persisted; folded by default).
    private(set) var completedExpanded = UserDefaults.standard.bool(forKey: completedExpandedKey)
    /// The last Complete / Move to Trash, offered in the action strip for a few seconds; or
    /// a brief notice.
    private(set) var undo: UndoOffer?
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
    /// Bumped by ⌘N (and on leaving search); the list focuses the New note field on change.
    private(set) var newNoteFocusRequests = 0
    /// Bumped by ⌘F and the search button; the list focuses the search field on change.
    private(set) var searchFocusRequests = 0

    /// Visible notes-list rows in display order (subtasks of expanded parents included); set by the list.
    @ObservationIgnored var visibleIDs: [UUID] = []
    /// The Trash view's rows in display order; set by the view.
    @ObservationIgnored var trashVisibleIDs: [UUID] = []
    /// The New note field has focus (Esc then skips the "end text edit" step).
    @ObservationIgnored var newNoteFieldFocused = false
    /// The search field has focus (Esc then leaves search; in any other text it ends that edit first).
    @ObservationIgnored var searchFieldFocused = false
    /// The row being renamed in place and how to cancel it (Esc).
    @ObservationIgnored var renaming: (id: UUID, cancel: () -> Void)?
    /// The click (its event number, shared by mouse-down and mouse-up) that ended a text edit by
    /// landing outside the field.
    @ObservationIgnored private var editEndingClick: Int?
    /// Set while the quick-capture strip shows under the New note field: Tab accepts its offer.
    @ObservationIgnored var quickCaptureAccept: (() -> Void)?
    /// The timer picker popover is showing; the window must not close when it takes key.
    @ObservationIgnored private(set) var timerPickerShown = false
    /// The "attach files" open panel is showing; the window must not close when it takes key.
    @ObservationIgnored private(set) var filePickerShown = false

    @ObservationIgnored var onOpenTaskChange: (() -> Void)?
    @ObservationIgnored var onTransientUIEnded: (() -> Void)?
    /// The open panel went away: the window takes key back.
    @ObservationIgnored var onFilePickerEnded: (() -> Void)?

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

    /// A click outside the text field being edited ends the edit (a row rename or the note's title
    /// commits). Not in the New note and search fields: they keep focus while the list is clicked.
    func clickEndsEdit(_ event: NSEvent) -> Bool {
        guard !newNoteFieldFocused, !searchFieldFocused else { return false }
        editEndingClick = event.eventNumber
        return true
    }

    /// A click on empty space in the list leaves search (back to New note, like Esc); otherwise it
    /// clears the selection, except a pinned note side's single note. A click that ended a text
    /// edit does only that.
    func emptySpaceClicked() {
        if let editEndingClick, editEndingClick == NSApp.currentEvent?.eventNumber { return }
        if searching {
            endSearch()
            return
        }
        if Self.isPinned && selection.single != nil { return }
        apply(.clear)
    }

    func open(_ id: UUID) { apply(.select(id)) }

    /// Shows the last clicked note alone (Return).
    func openCursor() {
        if let cursor = selection.cursor, visibleIDs.contains(cursor) { apply(.select(cursor)) }
    }

    func closeNoteSide() { apply(.clear) }

    /// Notes that were trashed or deleted: drop them from the selection.
    func tasksRemoved(_ ids: [UUID]) { apply(.removed(Set(ids))) }

    /// Drops selected ids that are no longer in the active list (e.g. changed by an agent).
    func pruneSelection(keeping active: Set<UUID>) {
        let gone = selection.ids.subtracting(active)
        if !gone.isEmpty { apply(.removed(gone)) }
    }

    // MARK: - Window signals

    func windowDidOpen() {
        showingTrash = false
        deleteConfirmation = nil
        searching = false
        searchQuery = ""
        undo = nil
        if !Self.isPinned || selection.single == nil { apply(.clear) }
        windowOpenCount += 1
    }

    /// Shows the Trash view; the note side closes, pinned or not.
    func showTrash() {
        searching = false
        searchQuery = ""
        trashSelection = SelectionModel.Selection()
        showingTrash = true
        apply(.clear)
    }

    /// Back from the Trash view to the notes list (the active Trash button, the back button, Esc).
    func leaveTrash() {
        showingTrash = false
        newNoteFocusRequests += 1
    }

    /// Selection in the Trash view: clicks, ↑/↓, ⌘A, and rows that left the Trash.
    func applyToTrash(_ input: SelectionModel.Input) {
        let next = SelectionModel.apply(input, to: trashSelection, visible: trashVisibleIDs)
        if next != trashSelection { trashSelection = next }
    }

    func focusNewNote() {
        showingTrash = false
        endSearch()
        newNoteFocusRequests += 1
    }

    // MARK: - Search

    /// The search button or ⌘F: the New note field becomes the search field (the button grows into it).
    func startSearch() {
        showingTrash = false
        if !searching { withAnimation(Self.searchAnimation) { searching = true } }
        searchFocusRequests += 1
    }

    /// Esc or a click on empty space while searching: back to the New note field.
    func endSearch() {
        guard searching else { return }
        withAnimation(Self.searchAnimation) { searching = false }
        searchQuery = ""
        newNoteFocusRequests += 1
    }

    private static var searchAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.2)
    }

    // MARK: - Completed group

    func toggleCompletedGroup() {
        completedExpanded.toggle()
        UserDefaults.standard.set(completedExpanded, forKey: Self.completedExpandedKey)
    }

    #if DEBUG
    /// Snapshots only: sets the fold without saving it.
    func snapshotSetCompletedExpanded(_ expanded: Bool) { completedExpanded = expanded }
    #endif

    // MARK: - Undo

    /// Shows the Undo strip for `undoDuration`; a newer offer replaces it (one level of undo).
    func offerUndo(_ message: String, restore: @escaping () -> Void) {
        show(UndoOffer(message: message, restore: restore), for: Self.undoDuration)
    }

    /// Shows a brief notice in the Undo strip's place, with no Undo button. Like a newer offer, it
    /// replaces a pending Undo.
    func showNotice(_ message: String) {
        show(UndoOffer(message: message, restore: nil), for: Self.noticeDuration)
    }

    private func show(_ offer: UndoOffer, for duration: TimeInterval) {
        undo = offer
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            if self?.undo?.id == offer.id { self?.undo = nil }
        }
    }

    /// The Undo button and ⌘Z. False when there is nothing to undo.
    @discardableResult
    func performUndo() -> Bool {
        guard let restore = undo?.restore else { return false }
        undo = nil
        restore()
        return true
    }

    func setTimerPickerShown(_ shown: Bool) {
        guard timerPickerShown != shown else { return }
        timerPickerShown = shown
        if !shown { onTransientUIEnded?() }
    }

    /// The plus of Attachments: the system open panel, for files and folders. It takes key, so the
    /// window is kept open underneath it (`filePickerShown`) and takes key back when it is done. It
    /// floats above the main window, which sits at the status bar level.
    func pickFiles(_ completion: @escaping ([URL]) -> Void) {
        guard !filePickerShown else { return }
        let open = NSOpenPanel()
        open.canChooseFiles = true
        open.canChooseDirectories = true
        open.allowsMultipleSelection = true
        open.prompt = "Attach"
        open.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        filePickerShown = true
        NSApp.activate()
        open.begin { [weak self] response in
            MainActor.assumeIsolated {
                self?.filePickerShown = false
                if response == .OK { completion(open.urls) }
                self?.onFilePickerEnded?()
            }
        }
    }
}
