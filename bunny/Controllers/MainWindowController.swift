import AppKit
import SwiftUI
import SwiftData

/// Owns Bunny's main window: one panel under the status item with the list and, when a note is open,
/// the note side. Places it from `WindowPlacement`, reveals the note side, closes it when it loses key,
/// and handles the keyboard (Esc, list navigation and shortcuts).
@MainActor
final class MainWindowController {
    static let height: CGFloat = 480

    private let panel: MainPanel
    private weak var statusButton: NSStatusBarButton?
    private let coordinator = PanelCoordinator.shared
    private let modelContext: ModelContext
    private var keyMonitor: Any?
    private var menuTracking = false
    /// The card with the note side open, in window coordinates (from `WindowPlacement`).
    private var card = CGRect.zero
    /// When the panel last closed itself on losing key; a status item click right after must not reopen it.
    private var lastAutoClose = Date.distantPast

    var isOpen: Bool { panel.isVisible }

    init(modelContainer: ModelContainer, statusButton: NSStatusBarButton) {
        self.statusButton = statusButton
        modelContext = modelContainer.mainContext
        let host = NSHostingView(rootView: MainWindowView()
            .modelContainer(modelContainer)
            .environment(AppState.shared)
            .environment(TimerManager.shared)
            .environment(PanelCoordinator.shared))
        // The window frame comes from WindowPlacement; don't let SwiftUI content resize the window.
        host.sizingOptions = []
        panel = MainPanel(content: host)
        panel.onResignKey = { [weak self] in
            // Let AppKit settle the new key window first (a popover or alert of ours keeps us open).
            DispatchQueue.main.async { self?.closeIfFocusLeft() }
        }
        panel.onOutsideClick = { [weak self] in self?.closeWindow() }
        panel.endsEditOnClick = { [coordinator] in coordinator.clickEndsEdit($0) }

        coordinator.onOpenTaskChange = { [weak self] in self?.updateNoteSide(animated: true) }
        coordinator.onTransientUIEnded = { [weak self] in self?.recheckFocusSoon() }
        coordinator.onFilePickerEnded = { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.panel.makeKey()
        }

        // Bunny's own context menus: never close underneath them.
        let center = NotificationCenter.default
        center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.menuTracking = true }
        }
        center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.menuTracking = false
                self?.recheckFocusSoon()
            }
        }

        // A local monitor rather than SwiftUI key handling: it sees every key in this non-activating
        // panel whether or not a SwiftUI view holds focus, and before menu key equivalents (⌘N, ⌘A).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
    }

    // MARK: - Open / close

    func toggle() {
        if panel.isVisible {
            closeWindow()
        } else if Date().timeIntervalSince(lastAutoClose) > 0.3 {
            openWindow()
        }
    }

    /// The global shortcut: closes the window when it is open and has the keyboard; otherwise opens it
    /// (or takes the keyboard back) with focus in the New note field.
    func toggleFromShortcut() {
        if panel.isVisible && panel.isKeyWindow {
            closeWindow()
        } else if panel.isVisible {
            panel.makeKey()
            coordinator.focusNewNote()
        } else {
            openWindow()
        }
    }

    /// Opens on the notes list with nothing open (the last note when the note side is pinned),
    /// focus in the New note field.
    func openWindow() {
        guard !panel.isVisible else { return }
        coordinator.windowDidOpen()
        place()
        updateNoteSide()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Opens the window on one note (e.g. from an agent notification).
    func openWindow(showing taskID: UUID) {
        openWindow()
        coordinator.open(taskID)
    }

    func closeWindow() {
        guard panel.isVisible else { return }
        // Ends in-progress edits so titles commit (and empty new subtasks are dropped).
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        coordinator.setTimerPickerShown(false)
        coordinator.deleteConfirmation = nil
        if !PanelCoordinator.isPinned { coordinator.closeNoteSide() }
    }

    // MARK: - Closing on focus loss

    private func closeIfFocusLeft() {
        guard panel.isVisible, !panel.isKeyWindow,
              !menuTracking, !coordinator.timerPickerShown, !coordinator.filePickerShown else { return }
        if let key = NSApp.keyWindow, isAttachedToPanel(key) { return }
        // The button is still down: this may be a drag on its way here. Decide when it is released:
        // released over the card (a drop), the window takes key and stays; anywhere else it closes.
        if NSEvent.pressedMouseButtons & 1 != 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.closeIfFocusLeft() }
            return
        }
        if panel.cardRect.contains(panel.mouseLocationOutsideOfEventStream) {
            panel.makeKey()
            return
        }
        lastAutoClose = Date()
        closeWindow()
    }

    /// After a transient UI goes away AppKit hands key back to the panel when the user stayed in Bunny;
    /// if key went to another app instead, the panel closes now.
    private func recheckFocusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.closeIfFocusLeft() }
    }

    /// A child window (popover) or sheet of the panel.
    private func isAttachedToPanel(_ window: NSWindow) -> Bool {
        var current: NSWindow? = window
        while let w = current {
            if w === panel { return true }
            current = w.parent ?? w.sheetParent
        }
        return false
    }

    // MARK: - Layout

    /// Places the window under the status item, wide enough for the list and the note side. The frame
    /// then stays put while the window is open; the note side is revealed inside it (`MainWindowView`).
    private func place() {
        guard let button = statusButton, let buttonWindow = button.window,
              let screen = buttonWindow.screen ?? NSScreen.main else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let placement = WindowPlacement.frame(anchor: anchor, visible: screen.visibleFrame, height: Self.height)
        coordinator.noteSide = placement.noteSide
        card = placement.card.offsetBy(dx: -placement.frame.minX, dy: -placement.frame.minY)
        panel.setFrame(placement.frame, display: true)
    }

    /// Shows or hides the note side. `animated`: opening or closing it in a visible window stretches the
    /// card out (or tucks it back in) instead of snapping, unless Reduce Motion is on; switching notes
    /// never animates. On close the note stays rendered until the card has tucked it away.
    private func updateNoteSide(animated: Bool = false) {
        let noteID = coordinator.openTaskID
        let shown = noteID != nil
        panel.cardRect = shown ? card : WindowPlacement.listFrame(card: card, noteSide: coordinator.noteSide)
        let animate = animated && panel.isVisible && coordinator.noteSideShown != shown
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animate else {
            coordinator.displayedNoteID = noteID
            coordinator.noteSideShown = shown
            return
        }
        if shown { coordinator.displayedNoteID = noteID }
        withAnimation(.easeInOut(duration: 0.22)) {
            coordinator.noteSideShown = shown
        } completion: { [weak self] in
            MainActor.assumeIsolated {
                // Closed and not reopened meanwhile: drop the note side now that it is out of view.
                guard let self, self.coordinator.openTaskID == nil else { return }
                self.coordinator.displayedNoteID = nil
            }
        }
    }

    // MARK: - Keyboard

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === panel else { return false }
        return event.keyCode == 53 ? handleEscape() : handleListKey(event)
    }

    /// ⌘Q quits and ⌘, opens Settings, from anywhere. ⌘N and ⌘F from anywhere. In the Trash view: ↑/↓ move the selection, ⌘A selects all, ⌫ / ⌘⌫
    /// delete the selection forever (after the confirmation). Otherwise: Tab accepts the quick-capture offer while its strip shows. The rest act
    /// on the notes list, only while no text field or editor has focus: ↑/↓ move the selection, ⌥↑/⌥↓
    /// move the note, Return shows the note, Space toggles complete, ⌫ / ⌘⌫ move to Trash, ⌘A selects
    /// all, ⌘V attaches a copied file or image to the open note. ⌘Z (undo) and ⌘C (copy as prompt)
    /// also work from the New note field while it is empty, which is where focus sits after opening
    /// the window.
    private func handleListKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command && key == "q" {
            NSApp.terminate(nil)
            return true
        }
        if flags == .command && key == "," {
            WindowManager.shared.showSettings()
            return true
        }
        // The delete confirmation takes no list shortcuts (nor ⌘N); Return picks its default, Cancel.
        if coordinator.deleteConfirmation != nil {
            if event.keyCode == 36 || event.keyCode == 76 {
                coordinator.deleteConfirmation = nil
                return true
            }
            return flags == .command && key == "n"
        }
        if flags == .command && key == "n" {
            coordinator.focusNewNote()
            return true
        }
        if flags == .command && key == "f" {
            coordinator.startSearch()
            return true
        }
        guard panel.isKeyWindow else { return false }
        if coordinator.showingTrash {
            switch (event.keyCode, flags) {
            case (126, []): coordinator.applyToTrash(.up)
            case (125, []): coordinator.applyToTrash(.down)
            case (_, .command) where key == "a": coordinator.applyToTrash(.selectAll)
            case (51, []), (51, .command):
                TaskActions.confirmDeleteForever(coordinator.trashSelection.ids, in: modelContext)
            default: return false
            }
            return true
        }
        let textView = panel.firstResponder as? NSTextView
        if event.keyCode == 48, flags.isEmpty, textView?.hasMarkedText() != true,
           let accept = coordinator.quickCaptureAccept {
            accept()
            return true
        }
        let selected = coordinator.selection.ids
        if textView == nil || (coordinator.newNoteFieldFocused && textView?.string.isEmpty == true) {
            if flags == .command && key == "z" { return coordinator.performUndo() }
            if flags == .command && key == "c" && !selected.isEmpty {
                TaskActions.copyAsPrompt(selected, in: modelContext)
                return true
            }
        }
        guard textView == nil else { return false }
        switch (event.keyCode, flags) {
        case (126, []): coordinator.apply(.up)
        case (125, []): coordinator.apply(.down)
        case (126, .option), (125, .option):
            // Not in search results: they are a filtered view with no order of their own.
            if let id = coordinator.selection.single, !coordinator.searching {
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                    TaskMover.step(id, up: event.keyCode == 126, in: modelContext)
                }
            }
        case (36, []), (76, []): coordinator.openCursor()
        case (49, []): TaskActions.toggleComplete(selected, in: modelContext, undoable: true)
        case (51, []), (51, .command): TaskActions.moveToTrash(selected, in: modelContext, undoable: true)
        case (_, .command) where key == "a": coordinator.apply(.selectAll)
        case (_, .command) where key == "v":
            guard let id = coordinator.openTaskID,
                  AttachmentRules.clipboardKind(types: ShelfService.clipboardTypes) != nil else { return false }
            ShelfService.attachClipboard(to: id, in: modelContext)
        default: return false
        }
        return true
    }

    /// Esc cancels the delete confirmation first, then a row rename, then ends a text edit (except in
    /// the New note and search fields), then leaves search, then clears a multi-selection, then closes
    /// the note side (unless pinned), then closes the window. In the Trash view it clears the
    /// selection, then goes back to the notes list. IME composition keeps its Esc.
    private func handleEscape() -> Bool {
        if coordinator.deleteConfirmation != nil {
            coordinator.deleteConfirmation = nil
            return true
        }
        let textView = panel.firstResponder as? NSTextView
        if textView?.hasMarkedText() == true { return false }
        if let renaming = coordinator.renaming {
            renaming.cancel()
            return true
        }
        if textView != nil && !coordinator.newNoteFieldFocused && !coordinator.searchFieldFocused {
            panel.makeFirstResponder(nil)
            return true
        }
        if coordinator.showingTrash {
            if coordinator.trashSelection.ids.isEmpty { coordinator.leaveTrash() } else { coordinator.applyToTrash(.clear) }
            return true
        }
        if coordinator.searching {
            coordinator.endSearch()
            return true
        }
        if coordinator.selection.ids.count > 1 || (coordinator.openTaskID != nil && !PanelCoordinator.isPinned) {
            coordinator.closeNoteSide()
        } else {
            closeWindow()
        }
        return true
    }
}
