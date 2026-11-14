#if DEBUG
import AppKit
import SwiftData
import SwiftUI

extension EnvironmentValues {
    /// The row or attachment tile drawn as hovered in a snapshot (real hover needs a pointer).
    @Entry var snapshotHoveredID: UUID?
    /// What the quick-capture strip offers in a snapshot (the real clipboard is never looked at).
    @Entry var snapshotClipboardOffer: AttachmentRules.ClipboardKind?
}

/// `bunny --snapshot <dir>` (Debug builds): renders fixed states of the main window to PNG files, in
/// dark and light, and exits. Nothing is shown and nothing of the user's is opened: the data is an
/// in-memory store with sample notes, the views are drawn in a window that is never ordered in, and
/// the status item, agents, Bunny tools server, scheduler and notifications are never started.
///
/// To add a state: append to `states`. `setUp` gets the sample notes and the coordinator after it was
/// reset; `width` and `height` are the card's size. `noteSide` builds a state of the full card with
/// one note open.
///
/// Drawn with `NSView.cacheDisplay`, which renders AppKit-backed controls (text fields, the details
/// text view, scroll views) that `ImageRenderer` leaves out. Not shown: hover and pressed states of
/// buttons, focus rings and carets, popovers and menus (separate windows), drag-and-drop highlights,
/// and animations (one frame only).
@MainActor
enum SnapshotRunner {
    /// The directory after `--snapshot`, when launched that way.
    static var outputDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(flag + 1) else { return nil }
        return URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
    }

    struct State {
        let name: String
        var empty = false
        var width = WindowPlacement.listWidth
        var height = MainWindowController.height
        var hovered: (Sample) -> UUID? = { _ in nil }
        var clipboardOffer: AttachmentRules.ClipboardKind?
        /// Drawn alone, at its own size, in place of the main window (a popover's content).
        var content: ((Sample) -> AnyView)?
        var setUp: (Sample, PanelCoordinator) -> Void = { _, _ in }
        /// Input sent to the laid-out window before it is drawn (see `Driver`).
        var act: (Driver) -> Void = { _ in }
        /// The switched-on agents and Bunny tools (in memory only).
        var agents: [AgentHarness] = [.claudeCode, .codex]
        var tools = false

        func then(_ more: @escaping (Driver) -> Void) -> State {
            var state = self
            let first = act
            state.act = { first($0); more($0) }
            return state
        }

        func agents(_ agents: [AgentHarness], tools: Bool = false) -> State {
            var state = self
            state.agents = agents
            state.tools = tools
            return state
        }
    }

    /// Sends key events straight to the snapshot window (`NSWindow.sendEvent`, in-process), so a state
    /// can show the result of typing. Mouse events sent this way do not reach SwiftUI's gestures in a
    /// window that is not on screen, so clicks are stood in for by calling the action they trigger.
    struct Driver {
        let window: NSWindow

        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

        /// Puts the caret in the first text field and inserts `text` as a paste would.
        func type(_ text: String) {
            guard let field = Self.find(NSTextField.self, in: window.contentView) else { return }
            window.makeFirstResponder(field)
            settle()
            (window.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
        }

        /// Puts the caret in the note side's details editor and types `text`.
        func typeDetails(_ text: String) {
            guard let editor = Self.find(DetailsTextView.self, in: window.contentView) else { return }
            window.makeFirstResponder(editor)
            editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
        }

        /// Types `text` in the "Message <Agent>…" field, puts the caret `offset` characters in,
        /// presses Shift-Return there and types on.
        func breakMessageLine(_ text: String, at offset: Int) {
            guard let field = Self.find(NSTextField.self, in: window.contentView, where: {
                ($0.placeholderString ?? $0.placeholderAttributedString?.string)?.hasPrefix("Message") == true
            }) else { return }
            window.makeFirstResponder(field)
            settle()
            guard let editor = window.firstResponder as? NSTextView else { return }
            editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            editor.setSelectedRange(NSRange(location: offset, length: 0))
            settle()
            pressReturn(modifiers: .shift)
            // Typed where the caret now is.
            editor.insertText("And ", replacementRange: NSRange(location: NSNotFound, length: 0))
            settle()
        }

        func pressReturn(modifiers: NSEvent.ModifierFlags = []) {
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                            windowNumber: window.windowNumber, context: nil, characters: "\r",
                                            charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36) {
                window.sendEvent(event)
            }
            settle()
        }

        private static func find<T: NSView>(_ type: T.Type, in view: NSView?, where matches: (T) -> Bool = { _ in true }) -> T? {
            guard let view else { return nil }
            if let match = view as? T, matches(match) { return match }
            for subview in view.subviews {
                if let match = find(type, in: subview, where: matches) { return match }
            }
            return nil
        }
    }

    static let states: [State] = [
        State(name: "list-default"),
        State(name: "list-hovered", hovered: { $0.plain.id }),
        State(name: "list-hovered-agents-off", hovered: { $0.plain.id }).agents([]),
        State(name: "list-one-selected", setUp: {  sample, coordinator in
            coordinator.apply(.select(sample.details.id))
        }),
        State(name: "list-three-selected", setUp: {  sample, coordinator in
            for note in [sample.plain, sample.long, sample.details] { coordinator.apply(.toggle(note.id)) }
        }),
        State(name: "list-completed-unfolded", height: 640, setUp: {  _, coordinator in
            if !coordinator.completedExpanded { coordinator.snapshotSetCompletedExpanded(true) }
        }),
        State(name: "list-search", setUp: {  _, coordinator in
            coordinator.startSearch()
            coordinator.searchQuery = "report"
        }),
        State(name: "list-search-empty-query", setUp: {  _, coordinator in
            coordinator.startSearch()
        }),
        State(name: "list-search-no-matches", setUp: {  _, coordinator in
            coordinator.startSearch()
            coordinator.searchQuery = "zebra"
        }),
        State(name: "list-undo", setUp: {  _, coordinator in
            coordinator.offerUndo(UndoRules.message(.trashed, count: 2)) {}
        }),
        State(name: "list-empty", empty: true),
        // Flows: each starts from what the one before left behind (the notes are rebuilt per appearance).
        State(name: "flow-1-add-multiline-note", act: { driver in
            driver.type("Call the bank about the card\nAsk why the fee doubled.\nReference 4471.")
            driver.pressReturn()
        }),
        State(name: "flow-2-complete", setUp: { sample, _ in
            TaskActions.toggleComplete([sample.plain.id], in: sample.context, undoable: true)
        }),
        State(name: "flow-3-undo-then-trash-pinned-parent", setUp: { sample, coordinator in
            TaskActions.toggleComplete([sample.plain.id], in: sample.context, undoable: true)
            coordinator.performUndo()
            AppState.shared.pinnedTaskID = sample.parent.id
            TaskActions.moveToTrash([sample.parent.id], in: sample.context, undoable: true)
        }),
        State(name: "flow-4-undo-trash", setUp: { sample, coordinator in
            // The reset between states dropped flow 3's undo: put the note back as it was, then
            // trash and undo in one go. The pin badge and both subtasks must be back.
            TaskActions.restoreFromTrash([sample.parent.id], in: sample.context)
            sample.parent.isPinned = true
            AppState.shared.pinnedTaskID = sample.parent.id
            TaskActions.moveToTrash([sample.parent.id], in: sample.context, undoable: true)
            coordinator.performUndo()
        }),
        State(name: "trash", setUp: {  _, coordinator in coordinator.showTrash() }),
        // ⌘A in the Trash view.
        State(name: "trash-all-selected", setUp: {  _, coordinator in coordinator.showTrash() }, act: { driver in
            PanelCoordinator.shared.applyToTrash(.selectAll)
            driver.settle()
        }),
        // Trashed from the list, then straight to the Trash: the Undo offer outranks the standing line.
        State(name: "trash-undo", setUp: {  _, coordinator in
            coordinator.offerUndo(UndoRules.message(.trashed, count: 1)) {}
            coordinator.showTrash()
        }),
        State(name: "trash-empty", empty: true, setUp: {  _, coordinator in coordinator.showTrash() }),
        State(name: "trash-delete-confirmation", setUp: {  _, coordinator in
            coordinator.showTrash()
            coordinator.deleteConfirmation = DeleteConfirmation(title: "Delete 3 notes forever?", confirmTitle: "Delete Forever") {}
        }),
        State(name: "list-selected-undo", setUp: { sample, coordinator in
            for note in [sample.plain, sample.details] { coordinator.apply(.toggle(note.id)) }
            coordinator.offerUndo(UndoRules.message(.completed, count: 1)) {}
        }),
        State(name: "timer-picker", width: 300, height: 190, content: { sample in
            AnyView(TimerPickerView(task: sample.review))
        }),
        State(name: "list-quick-capture", clipboardOffer: .image, act: { driver in
            driver.type("Send the new mockup to design")
        }),
        State(name: "list-quick-capture-file", clipboardOffer: .file, act: { driver in
            driver.type("File the signed contract")
        }),
        State(name: "list-copied-notice", setUp: { sample, coordinator in
            for note in [sample.plain, sample.details] { coordinator.apply(.toggle(note.id)) }
            coordinator.showNotice(UndoRules.copiedMessage(count: 2))
        }),
        State(name: "list-search-keeps-multiline-draft", act: { driver in
            driver.type("Call the bank about the card\nAsk why the fee doubled.\nReference 4471.")
            PanelCoordinator.shared.startSearch()
            driver.settle()
        }),
        // The note side. Details, three attachments (image, folder, missing file; the image hovered),
        // and the idle footer with Hand off.
        noteSide("note-attachments", hovered: { $0.imageAttachment.id }) { $0.details },
        noteSide("note-empty") { $0.plain },
        noteSide("note-long-details") { $0.long },
        // Typed text reaches the note (the row gets its details mark) and the editor grows with it.
        State(name: "note-typing-details", width: WindowPlacement.listWidth + WindowPlacement.noteWidth,
              setUp: { sample, coordinator in
                  coordinator.apply(.select(sample.review.id))
                  coordinator.displayedNoteID = sample.review.id
                  coordinator.noteSideShown = true
              }, act: { driver in
                  driver.typeDetails("Check the migration first.\nThen the tests: https://example.com/pull/42\n\nAsk Nikhil about the flaky one.")
              }),
        noteSide("note-subtask") { $0.subtask },
        // The agent part open, one state each (v3 spec §7).
        noteSide("note-needs-input") { $0.question },
        noteSide("note-needs-input-approval") { $0.approval },
        noteSide("note-agent-running") { $0.running },
        noteSide("note-agent-failed", agentOpen: true) { $0.failed },
        noteSide("note-agent-failed-details", agentOpen: true, configure: { AgentPanelState.shared.detailsOpen.insert($0.failed.id) }) { $0.failed },
        noteSide("note-agent-replied", agentOpen: true) { $0.replied },
        // Shift-Return with the caret between the two sentences: the line break goes there.
        noteSide("note-agent-message-newline", agentOpen: true) { $0.replied }
            .then { $0.breakMessageLine("Move them into old.keep the README.", at: 19) },
        noteSide("note-agent-finished", height: 620, agentOpen: true) { $0.finished },
        noteSide("note-agent-thread-expanded", height: 760, agentOpen: true, configure: {
            AgentPanelState.shared.threadExpanded.insert($0.finished.id)
            AgentPanelState.shared.messagesExpanded.insert($0.finished.id)
        }) { $0.finished },
        noteSide("note-agent-stopped", agentOpen: true) { $0.stopped },
        // The note open, the agent folded to one row above the footer.
        noteSide("note-agent-folded", agentOpen: false) { $0.running },
        noteSide("note-agent-folded-finished", agentOpen: false) { $0.finished },
        // The Welcome window's two pages (its content; the title bar is not shown).
        welcome("welcome-1", page: 0),
        welcome("welcome-2-found", page: 1, found: [.claudeCode: true, .codex: true]).agents([.claudeCode]),
        welcome("welcome-2-not-found", page: 1, found: [.claudeCode: true, .codex: false]).agents([]),
        // Both agents off: no Hand off anywhere, but a note's old agent section stays.
        noteSide("note-agents-off") { $0.failed }.agents([]),
        noteSide("note-plain-agents-off") { $0.details }.agents([]),
        // The Hand off options card, over a note with an attached folder.
        noteSide("note-handoff-card", card: true) { $0.details },
        noteSide("note-handoff-card-claude-only", card: true) { $0.plain }.agents([.claudeCode]),
        // The Settings window's content, one state per page. Not shown: the title bar (the sidebar
        // starts below it in the real window), and the menus of the pop-up buttons.
        settings("settings-general", page: .general),
        settings("settings-appearance", page: .appearance),
        settings("settings-notes", page: .notes),
        settings("settings-agents", page: .agents),
        settings("settings-agents-off", page: .agents).agents([]),
        settings("settings-agents-claude-only", page: .agents).agents([.claudeCode]),
        settings("settings-agents-advanced", page: .agents, height: 1500) { $0.advancedExpanded = true }.agents([.claudeCode, .codex], tools: true),
        settings("settings-agents-advanced-tools-off", page: .agents, height: 1500) { $0.advancedExpanded = true },
        settings("settings-data", page: .data),
        settings("settings-about", page: .about),
        // "trash" typed in the sidebar, and its second result chosen.
        settings("settings-search", page: .general) { model in
            model.query = "trash"
            model.reveal(SettingsCatalog.row(.trashRetention))
        },
        settings("settings-search-no-results", page: .general) { $0.query = "zebra" },
    ]

    /// The Settings window's content on one page, with fixed sample values (`settingsLive` off).
    private static func settings(_ name: String, page: SettingsCatalog.Page, height: CGFloat = 540,
                                 configure: @escaping (SettingsModel) -> Void = { _ in }) -> State {
        State(name: name, width: 780, height: height, content: { _ in
            let model = SettingsModel()
            model.page = page
            configure(model)
            return AnyView(SettingsView().environment(model).environment(\.settingsLive, false))
        })
    }

    private static func welcome(_ name: String, page: Int, found: [AgentHarness: Bool] = [:]) -> State {
        State(name: name, width: OnboardingView.size.width, height: OnboardingView.size.height, content: { _ in
            AnyView(OnboardingView(page: page, found: found, live: false))
        })
    }

    /// The full card (list and note side) with one note open. `agentOpen`: which part of a handed-off
    /// note is open (nil: the default for its state); `configure` sets what is unfolded.
    private static func noteSide(_ name: String, height: CGFloat? = nil,
                                 hovered: @escaping (Sample) -> UUID? = { _ in nil }, card: Bool = false,
                                 agentOpen: Bool? = nil, configure: @escaping (Sample) -> Void = { _ in },
                                 _ note: @escaping (Sample) -> BunnyTask) -> State {
        State(name: name, width: WindowPlacement.listWidth + WindowPlacement.noteWidth, height: height ?? MainWindowController.height, hovered: hovered,
              setUp: { sample, coordinator in
                  let id = note(sample).id
                  let panelState = AgentPanelState.shared
                  panelState.threadExpanded = []
                  panelState.messagesExpanded = []
                  panelState.detailsOpen = []
                  configure(sample)
                  coordinator.apply(.select(id))
                  // What the window controller does when a note opens.
                  coordinator.displayedNoteID = id
                  coordinator.noteSideShown = true
                  if card { coordinator.handOffCardTaskID = id }
              }, act: { driver in
                  // After the note side appeared (it picks the default part then).
                  if let agentOpen, let id = PanelCoordinator.shared.openTaskID {
                      AgentPanelState.shared.agentOpen[id] = agentOpen
                      driver.settle()
                  }
              })
    }

    static func run(to directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let coordinator = PanelCoordinator.shared
            CodexModelStore.shared.snapshotSet([
                CodexModel(id: "gpt-5.5-codex", displayName: "GPT-5.5 Codex", efforts: ["low", "medium", "high"],
                           defaultEffort: "medium", isDefault: true),
            ])
            for dark in [true, false] {
                let full = try ModelContainer(for: BunnyTask.self, ShelfItem.self, configurations: configuration)
                let empty = try ModelContainer(for: BunnyTask.self, ShelfItem.self, configurations: configuration)
                let sample = Sample(in: full.mainContext)
                NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                for state in states {
                    coordinator.snapshotReset()
                    AgentEnablement.shared.snapshotSet(state.agents, tools: state.tools)
                    state.setUp(sample, coordinator)
                    let view = (state.content?(sample) ?? AnyView(MainWindowView()))
                        .environment(\.snapshotHoveredID, state.hovered(sample))
                        .environment(\.snapshotClipboardOffer, state.clipboardOffer)
                        .modelContainer(state.empty ? empty : full)
                        .environment(AppState.shared)
                        .environment(TimerManager.shared)
                        .environment(coordinator)
                    let size = CGSize(width: state.width + 2 * WindowPlacement.shadowMargin,
                                      height: state.height + WindowPlacement.shadowMargin + WindowPlacement.gap)
                    let url = directory.appendingPathComponent("\(state.name)-\(dark ? "dark" : "light").png")
                    try render(view, size: size, dark: dark, act: state.act).write(to: url)
                    print(url.path)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
            exit(1)
        }
    }

    /// Lays the view out in an off-screen window (never ordered in), lets SwiftUI settle, and draws it
    /// over a flat backdrop standing in for the desktop.
    private static func render(_ view: some View, size: CGSize, dark: Bool, act: (Driver) -> Void) throws -> Data {
        let backdrop = Color(white: dark ? 0.22 : 0.78)
        let host = NSHostingView(rootView: view.background(backdrop).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // onChange / onAppear / queries / async focus requests run on the main run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        act(Driver(window: window))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        window.contentView = nil
        return png
    }

    /// The sample notes: one of each thing a row can show.
    struct Sample {
        let context: ModelContext
        let plain: BunnyTask
        let long: BunnyTask
        let details: BunnyTask
        let parent: BunnyTask
        let subtask: BunnyTask
        let review: BunnyTask
        let running: BunnyTask
        let question: BunnyTask
        let failed: BunnyTask
        let approval: BunnyTask
        let finished: BunnyTask
        let replied: BunnyTask
        let stopped: BunnyTask
        let imageAttachment: ShelfItem

        init(in context: ModelContext) {
            self.context = context
            var order = 0
            func note(_ title: String, parent: BunnyTask? = nil, _ configure: (BunnyTask) -> Void = { _ in }) -> BunnyTask {
                let task = BunnyTask(title: title, parentID: parent?.id, sortOrder: order)
                order += 1
                configure(task)
                context.insert(task)
                return task
            }
            func complete(_ task: BunnyTask, minutesAgo: Double, byAgent: Bool = false) {
                task.isCompleted = true
                task.completedAt = Date().addingTimeInterval(-60 * minutesAgo)
                task.completedByAgent = byAgent
            }

            plain = note("Book flights for the offsite")
            long = note("Write up the notes from Thursday's planning meeting and send them to everyone who could not make it") {
                $0.createdAt = Date().addingTimeInterval(-86_400 * 9)
                $0.taskDescription = (1...7).map { """
                    \($0). Agenda item \($0): what was decided, who owns it and by when. Open points go \
                    to the tracker at https://example.com/tracker/\($0)00 so nothing is lost.
                    """ }.joined(separator: "\n\n")
            }
            details = note("Draft the quarterly report") {
                $0.createdAt = Date().addingTimeInterval(-86_400)
                $0.taskDescription = "Numbers are in the finance sheet: https://example.com/finance/q3. Keep it to two pages."
            }
            // An image and a folder that exist (in the temporary directory), and a file that is gone.
            let files = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-snapshot", isDirectory: true)
            let image = files.appendingPathComponent("whiteboard-photo-from-the-planning-session.png")
            let folder = files.appendingPathComponent("Charts", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Self.sampleImage().write(to: image)
            let detailsID = details.id
            func attachment(_ url: URL, isDirectory: Bool = false, order: Int) -> ShelfItem {
                let item = ShelfItem(taskID: detailsID, bookmark: (try? url.bookmarkData()) ?? Data(), url: url,
                                     isDirectory: isDirectory, sortOrder: order)
                context.insert(item)
                return item
            }
            imageAttachment = attachment(image, order: 0)
            _ = attachment(folder, isDirectory: true, order: 1)
            _ = attachment(URL(fileURLWithPath: "/Users/sample/Documents/q3-numbers.xlsx"), order: 2)
            parent = note("Plan the launch") { $0.isPinned = true }
            _ = note("Pick a date", parent: parent) { complete($0, minutesAgo: 30) }
            subtask = note("Write the announcement", parent: parent) {
                $0.taskDescription = "Short, plain, with the date in the first line."
            }
            review = note("Review the pull request") {
                $0.timerDuration = 25 * 60
                $0.timerStartedAt = Date().addingTimeInterval(-7 * 60 - 18)
            }
            running = note("Fix the flaky login test") {
                $0.runState = .running
                $0.agentActivity = "Running the test suite"
                $0.agentSessionID = "sample-session-3"
                $0.agentStartedAt = Date().addingTimeInterval(-95)
                $0.agentHarness = AgentHarness.claudeCode.rawValue
                $0.agentWorkingDirectory = NSHomeDirectory() + "/Projects/login-service"
                $0.taskDescription = "It fails about one run in ten on CI, never locally. Probably the session cookie race.\nLogs are attached."
                $0.agentThreadData = Self.thread([
                    (.agent, "The test waits on a fixed 200 ms sleep. I can replace it with a wait on the session event."),
                    (.user, "Yes, do that. And run the whole suite, not only this test."),
                ])
            }
            question = note("Migrate the settings screen") {
                $0.runState = .needsInput
                $0.agentSessionID = "sample-session"
                $0.agentStartedAt = Date().addingTimeInterval(-340)
                $0.agentQuestionData = try? JSONEncoder().encode(AgentQuestion(kind: .choices, items: [
                    AgentQuestionItem(key: "navigation", header: "Navigation",
                                      question: "Which navigation should the new settings screen use?",
                                      options: [AgentQuestionOption(label: "Sidebar", detail: "Six pages, like System Settings"),
                                                AgentQuestionOption(label: "Tabs", detail: "A toolbar with one tab per page")],
                                      multiSelect: false, allowsOther: true),
                ]))
            }
            failed = note("Update the changelog script") {
                $0.runState = .failed
                $0.agentSummary = "error: unexpected argument '--effort' found\n\nUsage: codex app-server [OPTIONS]\n\nFor more information, try '--help'.\nexited with code 2"
                $0.agentStartedAt = Date().addingTimeInterval(-70)
                $0.agentFinishedAt = Date().addingTimeInterval(-66)
                $0.agentHarness = AgentHarness.codex.rawValue
                $0.agentSessionID = "sample-session-4"
                $0.agentWorkingDirectory = NSHomeDirectory() + "/Projects/tools"
            }
            approval = note("Clean up the old build folders") {
                $0.runState = .needsInput
                $0.agentHarness = AgentHarness.codex.rawValue
                $0.agentSessionID = "sample-session-5"
                $0.agentStartedAt = Date().addingTimeInterval(-48)
                $0.agentActivity = "Running ls build"
                $0.agentQuestionData = try? JSONEncoder().encode(AgentQuestion(
                    kind: .approval, items: [], approvalTitle: "Run command",
                    approvalDetail: "rm -rf build/intermediates build/tmp", requestID: "7", method: "execCommandApproval", rawInput: nil))
            }
            stopped = note("Sort the screenshots folder") {
                $0.runState = .stopped
                $0.agentHarness = AgentHarness.claudeCode.rawValue
                $0.agentSessionID = "sample-session-6"
                $0.agentActivity = "Interrupted — Bunny quit"
                $0.agentStartedAt = Date().addingTimeInterval(-900)
                $0.agentFinishedAt = Date().addingTimeInterval(-600)
            }
            replied = note("Clear out the exports folder") {
                $0.runState = .replied
                $0.agentHarness = AgentHarness.claudeCode.rawValue
                $0.agentSessionID = "sample-session-8"
                $0.agentStartedAt = Date().addingTimeInterval(-200)
                $0.agentFinishedAt = Date().addingTimeInterval(-170)
                $0.agentWorkingDirectory = NSHomeDirectory() + "/Projects/exports"
                $0.agentThreadData = Self.thread([
                    (.user, "What do you see in this folder?"),
                    (.agent, "Three CSV exports from March, a README, and an empty folder named old. Should I delete the CSVs, or move them into old?"),
                ])
            }
            finished = note("Add a dark mode to the docs site") {
                complete($0, minutesAgo: 11, byAgent: true)
                $0.runState = .finished
                $0.agentHarness = AgentHarness.claudeCode.rawValue
                $0.agentSessionID = "sample-session-7"
                $0.agentStartedAt = Date().addingTimeInterval(-1_300)
                $0.agentFinishedAt = Date().addingTimeInterval(-700)
                $0.agentWorkingDirectory = NSHomeDirectory() + "/Projects/docs"
                let summary = """
                    Dark mode is in. The site follows the system setting and has a switch in the header that \
                    remembers the choice.

                    Changed: theme.css (a second palette under prefers-color-scheme), header.html (the switch), \
                    and site.js (stores the choice). Code blocks use a darker variant of the same syntax theme.

                    Not done: the three diagrams on the Architecture page are PNGs with a white background. \
                    Preview: https://example.com/docs-preview/dark
                    """
                $0.agentSummary = summary
                $0.agentThreadData = Self.thread([
                    (.agent, "Which pages should get it first?"),
                    (.user, "All of them"),
                    (.agent, "Done: every page has both palettes now. Want a switch in the header too?"),
                    (.user, "Yes, and remember the choice."),
                    (.user, "Keep the code blocks readable."),
                    (.agent, summary),
                ])
            }
            _ = note("Renew the domain") { complete($0, minutesAgo: 5) }
            _ = note("Send the expense report") { complete($0, minutesAgo: 50) }
            _ = note("Tidy the build warnings") {
                complete($0, minutesAgo: 20, byAgent: true)
                $0.runState = .finished
                $0.agentSessionID = "sample-session-2"
            }
            _ = note("Reply to the landlord") { complete($0, minutesAgo: 90) }

            let day: TimeInterval = 86_400
            _ = note("Annual report cover design") {
                complete($0, minutesAgo: 60 * 26)
                $0.deletedAt = Date().addingTimeInterval(-2 * day)
            }
            _ = note("Cancel the old hosting plan") {
                complete($0, minutesAgo: 60 * 30)
                $0.deletedAt = Date().addingTimeInterval(-12 * day)
            }
            _ = note("Old report drafts") { $0.deletedAt = Date().addingTimeInterval(-day) }
            try? context.save()
        }

        private static func thread(_ messages: [(AgentThread.Role, String)]) -> Data? {
            var data: Data?
            for (index, message) in messages.enumerated() {
                data = AgentThread.appending(message.0, message.1, at: Date().addingTimeInterval(Double(index - messages.count) * 60), to: data)
            }
            return data
        }

        /// A small picture for the image attachment's thumbnail.
        private static func sampleImage() -> Data {
            let image = NSImage(size: NSSize(width: 320, height: 200), flipped: false) { rect in
                NSGradient(colors: [.systemTeal, .systemIndigo])?.draw(in: rect, angle: 35)
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: 60, y: 50, width: 90, height: 90)).fill()
                NSBezierPath(roundedRect: NSRect(x: 180, y: 60, width: 90, height: 60), xRadius: 10, yRadius: 10).fill()
                return true
            }
            return image.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) } ?? Data()
        }
    }
}

extension PanelCoordinator {
    /// Back to what a freshly opened window shows, with the Completed group folded.
    func snapshotReset() {
        windowDidOpen()
        apply(.clear)
        displayedNoteID = nil
        noteSideShown = false
        snapshotSetCompletedExpanded(false)
        handOffCardTaskID = nil
    }
}
#endif
