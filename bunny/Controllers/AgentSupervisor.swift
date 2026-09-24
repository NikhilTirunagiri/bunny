import Foundation
import Observation
import SwiftData
import UserNotifications

/// Owns every background agent run: one runner per task, and all writes of the task's agent fields (spec §7).
@MainActor
@Observable
final class AgentSupervisor {
    static let shared = AgentSupervisor()
    private init() {}

    /// Tasks in `needsInput` (drives the menu-bar dot).
    private(set) var attentionCount: Int = 0

    /// Live runners keyed by task id. A runner leaves this map when its task stops being active,
    /// so events from a retired runner (e.g. the `exited` after a terminate) are ignored.
    private var runners: [UUID: AgentRunner] = [:]

    private enum WrapUpPhase {
        /// Timer expired: the turn was interrupted; the wrap-up message has not been sent yet.
        case interrupting
        /// The wrap-up message was sent; its reply is the summary.
        case awaitingSummary
    }

    @ObservationIgnored private var modelContainer: ModelContainer?
    @ObservationIgnored private var wrapUps: [UUID: WrapUpPhase] = [:]
    /// Subtask ids in the order they were numbered in the brief (for `<bunny-subtasks-done>`).
    @ObservationIgnored private var briefSubtaskIDs: [UUID: [UUID]] = [:]
    /// Tasks whose timer was already seen expired, so an expiry is acted on once, when it flips.
    @ObservationIgnored private var expiredTimers: Set<UUID> = []
    @ObservationIgnored private var checkTimer: Timer?

    private static let wrapUpMessage = "Time's up — stop here and reply with a summary of what's done and what's left."
    private static let timeRanOutSuffix = " · Time ran out"

    private var context: ModelContext? { modelContainer?.mainContext }

    // MARK: - Setup

    /// Called once from AppDelegate. Recovers runs interrupted by quitting Bunny (spec §7).
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer

        for task in allTasks() {
            if task.runState == .running {
                task.runState = .stopped
                task.agentActivity = "Interrupted — Bunny quit"
                task.agentFinishedAt = task.agentFinishedAt ?? Date()
            }
            // needsInput stays: answering resumes the session.
            if task.isTimerExpired {
                expiredTimers.insert(task.id)
            }
        }
        didChangeState()

        checkTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.checkTimers()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
    }

    // MARK: - Queries

    func isLive(_ taskID: UUID) -> Bool {
        runners[taskID] != nil
    }

    // MARK: - Actions

    /// No session yet → start with the default harness; otherwise open the session (never a duplicate run).
    func primaryAction(for task: BunnyTask) {
        if task.agentSessionID == nil && !task.runState.isActive {
            start(task, harness: nil)
        } else {
            openSession(task)
        }
    }

    func start(_ task: BunnyTask, harness: AgentHarness?) {
        guard context != nil, !task.runState.isActive, runners[task.id] == nil else { return }
        let harness = harness ?? AgentSettings.defaultHarness

        wrapUps[task.id] = nil

        guard cliIsAvailable(for: harness) else {
            // Keeps any previous harness/session pair intact, so that session can still be opened.
            failMissingCLI(task, harness: harness)
            return
        }
        // A new run is a new session (the previous one, if any, is replaced on `sessionStarted`).
        task.agentHarness = harness.rawValue
        task.agentSessionID = nil
        task.agentQuestionData = nil

        // Starting the agent starts the task's timer, so the brief carries the deadline.
        if task.timerDuration != nil && task.timerStartedAt == nil {
            task.timerStartedAt = Date()
        }
        if task.isTimerExpired {
            // Already expired before the run: no deadline, and no wrap-up for an old expiry.
            expiredTimers.insert(task.id)
        } else {
            expiredTimers.remove(task.id)
        }

        let brief = makeBrief(for: task, workingDirectory: nil)
        task.agentWorkingDirectory = brief.workingDirectory
        task.runState = .running
        task.agentStartedAt = Date()
        task.agentFinishedAt = nil
        task.agentSummary = ""
        task.agentActivity = "Starting…"
        didChangeState()

        launch(task.id, harness: harness, brief: brief, resumeSessionID: nil, initialMessage: nil)
    }

    func answer(_ task: BunnyTask, with answer: AgentAnswer) {
        guard task.runState == .needsInput, let question = task.pendingQuestion else { return }

        if let runner = runners[task.id] {
            runner.answer(question, with: answer)
            task.runState = .running
            task.agentQuestionData = nil
            task.agentActivity = "Continuing…"
            didChangeState()
            return
        }

        // No live runner (Bunny was restarted, or the process exited): resume the session with the answer.
        let harness = task.harness ?? AgentSettings.defaultHarness
        guard cliIsAvailable(for: harness) else {
            // Keep the question so the owner can answer again after fixing the path.
            task.agentActivity = "\(harness.displayName) not found — set its path in Settings → Agents."
            didChangeState()
            return
        }

        let brief = makeBrief(for: task, workingDirectory: task.agentWorkingDirectory)
        let questionText = Self.questionText(question)
        let summary = answer.summary(for: question)
        let resumeMessage = "Answer to your earlier question \"\(questionText)\": \(summary)"

        task.agentHarness = harness.rawValue
        task.agentWorkingDirectory = brief.workingDirectory
        task.runState = .running
        task.agentQuestionData = nil
        task.agentFinishedAt = nil
        task.agentActivity = "Resuming…"
        didChangeState()

        if let sessionID = task.agentSessionID {
            launch(task.id, harness: harness, brief: brief, resumeSessionID: sessionID, initialMessage: resumeMessage)
        } else {
            // No session to resume: start over with the brief plus the answer.
            let prompt = AgentPromptBuilder.prompt(for: brief, now: Date()) + "\n\n" + resumeMessage
            launch(task.id, harness: harness, brief: brief, resumeSessionID: nil, initialMessage: prompt)
        }
    }

    /// Interrupt, then terminate after 3 s (so the CLI can save the session). State `stopped`.
    func stop(_ task: BunnyTask) {
        if let runner = runners.removeValue(forKey: task.id) {
            runner.interrupt()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                runner.terminate()
            }
        }
        wrapUps[task.id] = nil
        guard task.runState.isActive else {
            didChangeState()
            return
        }
        task.runState = .stopped
        task.agentActivity = "Stopped"
        task.agentQuestionData = nil
        task.agentFinishedAt = Date()
        didChangeState()
    }

    func openSession(_ task: BunnyTask) {
        guard let sessionID = task.agentSessionID else {
            start(task, harness: nil)
            return
        }
        let harness = task.harness ?? AgentSettings.defaultHarness

        if task.runState.isActive {
            // One process per session: stop the background one before the owner takes over.
            if let runner = runners.removeValue(forKey: task.id) {
                runner.terminate()
            }
            wrapUps[task.id] = nil
            task.runState = .handedOff
            task.agentQuestionData = nil
            task.agentFinishedAt = Date()
            task.agentActivity = "Opened in \(AgentSettings.openIn.displayName)"
        }

        let cwd = task.agentWorkingDirectory ?? AgentSettings.defaultWorkspace
        if let fallback = SessionLauncher.open(harness: harness, sessionID: sessionID, cwd: cwd) {
            task.agentActivity = "Couldn't open the app — resume command copied: \(fallback)"
        }
        didChangeState()
    }

    /// Resets the agent fields of a task that isn't running an agent.
    func clear(_ task: BunnyTask) {
        guard !task.runState.isActive else { return }
        if let runner = runners.removeValue(forKey: task.id) {
            runner.terminate()
        }
        wrapUps[task.id] = nil
        briefSubtaskIDs[task.id] = nil
        task.agentHarness = nil
        task.runState = .idle
        task.agentSessionID = nil
        task.agentWorkingDirectory = nil
        task.agentActivity = ""
        task.agentSummary = ""
        task.agentQuestionData = nil
        task.agentStartedAt = nil
        task.agentFinishedAt = nil
        didChangeState()
    }

    /// Called before a task is archived or deleted: stops its live runner.
    func taskWillArchiveOrDelete(_ taskID: UUID) {
        if let task = task(with: taskID) {
            stop(task)
        } else if let runner = runners.removeValue(forKey: taskID) {
            runner.terminate()
            wrapUps[taskID] = nil
        }
        briefSubtaskIDs[taskID] = nil
        expiredTimers.remove(taskID)
    }

    // MARK: - Launch

    private func launch(_ taskID: UUID, harness: AgentHarness, brief: AgentBrief, resumeSessionID: String?, initialMessage: String?) {
        let options = AgentRunOptions(
            cliPath: AgentSettings.cliPath(for: harness),
            autonomy: AgentSettings.autonomy,
            environment: ShellEnvironment.environment()
        )
        let runner: AgentRunner
        switch harness {
        case .claudeCode: runner = ClaudeCodeRunner(options: options)
        case .codex: runner = CodexRunner(options: options)
        }

        runners[taskID] = runner
        // The task id is captured, so two concurrent runs never cross wires.
        runner.onEvent = { [weak self, weak runner] event in
            guard let self, let runner else { return }
            self.handle(event, taskID: taskID, from: runner)
        }
        runner.start(brief: brief, harness: harness, resumeSessionID: resumeSessionID, initialMessage: initialMessage)
    }

    private func cliIsAvailable(for harness: AgentHarness) -> Bool {
        let path = AgentSettings.cliPath(for: harness)
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private func failMissingCLI(_ task: BunnyTask, harness: AgentHarness) {
        task.runState = .failed
        task.agentSummary = "\(harness.displayName) not found — set its path in Settings → Agents."
        task.agentActivity = ""
        task.agentFinishedAt = Date()
        didChangeState()
    }

    /// `workingDirectory`: the session's recorded directory when resuming (sessions are stored per directory).
    private func makeBrief(for task: BunnyTask, workingDirectory: String?) -> AgentBrief {
        let subtasks = subtasks(of: task)
        briefSubtaskIDs[task.id] = subtasks.map(\.id)

        var shelf: [AgentBrief.ShelfEntry] = []
        if let context {
            for item in ShelfService.items(for: task.id, in: context) where ShelfService.resolve(item) != nil {
                shelf.append(AgentBrief.ShelfEntry(path: item.lastKnownPath, isDirectory: item.isDirectory))
            }
        }

        var deadline: Date?
        if let duration = task.timerDuration, let startedAt = task.timerStartedAt, !task.isTimerExpired {
            deadline = startedAt.addingTimeInterval(duration)
        }

        var resolved = WorkingDirectoryResolver.resolve(shelf: shelf, defaultWorkspace: AgentSettings.defaultWorkspace)
        if let workingDirectory, !workingDirectory.isEmpty {
            resolved.cwd = workingDirectory
            resolved.extra.removeAll { $0 == workingDirectory }
        }

        return AgentBrief(
            title: task.title,
            description: task.taskDescription,
            subtasks: subtasks.map { AgentBrief.Subtask(title: $0.title, done: $0.isCompleted) },
            shelf: shelf,
            deadline: deadline,
            workingDirectory: resolved.cwd,
            extraDirectories: resolved.extra
        )
    }

    private func subtasks(of task: BunnyTask) -> [BunnyTask] {
        allTasks()
            .filter { $0.parentID == task.id && $0.archivedAt == nil }
            .sorted { lhs, rhs in
                lhs.sortOrder != rhs.sortOrder ? lhs.sortOrder < rhs.sortOrder : lhs.createdAt < rhs.createdAt
            }
    }

    // MARK: - Events

    private func handle(_ event: AgentEvent, taskID: UUID, from runner: AgentRunner) {
        // Ignore events from a runner that was retired (stopped, handed off, finished, replaced).
        guard let current = runners[taskID], current === runner else { return }
        guard let task = task(with: taskID) else {
            runners[taskID] = nil
            runner.terminate()
            return
        }

        switch event {
        case let .sessionStarted(id):
            task.agentSessionID = id

        case let .activity(text):
            // Frequent and not a state change: leave persistence to SwiftData's autosave.
            task.agentActivity = text
            return

        case let .question(question):
            wrapUps[taskID] = nil
            task.runState = .needsInput
            task.agentQuestionData = try? JSONEncoder().encode(question)
            notify("\(task.title) needs your input", taskID: taskID)

        case let .turnFinished(text, success):
            if wrapUps[taskID] == .interrupting {
                // The interrupted turn ended: keep the runner and ask for the wrap-up summary now.
                sendWrapUp(taskID)
                return
            }
            finishTurn(task, text: text, success: success)
            runners[taskID] = nil
            // One turn per handoff: follow-ups resume the session in a new process.
            runner.terminate()

        case let .failed(message):
            wrapUps[taskID] = nil
            task.runState = .failed
            task.agentSummary = message
            task.agentQuestionData = nil
            task.agentFinishedAt = Date()
            runners[taskID] = nil
            runner.terminate()

        case .exited:
            wrapUps[taskID] = nil
            runners[taskID] = nil
            if task.runState == .running {
                task.runState = .failed
                task.agentSummary = "Agent exited unexpectedly"
                task.agentFinishedAt = Date()
            }
            // needsInput stays: with no live runner, answering resumes the session.
        }
        didChangeState()
    }

    private func finishTurn(_ task: BunnyTask, text: String, success: Bool) {
        let now = Date()
        if wrapUps.removeValue(forKey: task.id) == .awaitingSummary {
            // Timer ran out: the reply is a summary, not a completion (no green).
            task.runState = .stopped
            task.agentSummary = applyCompletedSubtasks(text, to: task, at: now)
            task.agentActivity = "Time ran out"
        } else if success {
            task.runState = .finished
            task.isCompleted = true
            task.completedAt = now
            task.completedByAgent = true
            task.agentSummary = applyCompletedSubtasks(text, to: task, at: now)
            task.agentActivity = "Done"
            notify("\(task.title) is done", taskID: task.id)
        } else {
            task.runState = .failed
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            task.agentSummary = trimmed.isEmpty ? "The agent's turn failed" : trimmed
        }
        task.agentFinishedAt = now
        task.agentQuestionData = nil
    }

    /// Marks the subtasks named by `<bunny-subtasks-done>` (1-based, brief order) done and returns the cleaned text.
    private func applyCompletedSubtasks(_ text: String, to task: BunnyTask, at now: Date) -> String {
        let (cleaned, numbers) = AgentMarkers.extractCompletedSubtasks(from: text)
        guard !numbers.isEmpty else { return cleaned }

        let byID = Dictionary(allTasks().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = (briefSubtaskIDs[task.id] ?? subtasks(of: task).map(\.id)).compactMap { byID[$0] }
        for number in Set(numbers) where number >= 1 && number <= ordered.count {
            let subtask = ordered[number - 1]
            guard !subtask.isCompleted else { continue }
            subtask.isCompleted = true
            subtask.completedAt = now
            subtask.completedByAgent = true
        }
        return cleaned
    }

    // MARK: - Timer

    private func checkTimers() {
        guard context != nil else { return }
        let tasks = allTasks()
        for task in tasks {
            guard task.isTimerExpired else {
                expiredTimers.remove(task.id)
                continue
            }
            guard expiredTimers.insert(task.id).inserted else { continue }

            switch task.runState {
            case .running:
                guard let runner = runners[task.id], wrapUps[task.id] == nil else { continue }
                wrapUps[task.id] = .interrupting
                task.agentActivity = "Time's up — wrapping up…"
                runner.interrupt()
                let taskID = task.id
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    self?.sendWrapUp(taskID)
                }
            case .needsInput:
                if !task.agentActivity.hasSuffix(Self.timeRanOutSuffix) {
                    task.agentActivity += Self.timeRanOutSuffix
                }
            default:
                break
            }
        }
        // Also picks up archives/deletions made elsewhere.
        recomputeAttention(tasks)
    }

    /// Sends the wrap-up request once: when the interrupted turn ends, or 1 s after the interrupt.
    private func sendWrapUp(_ taskID: UUID) {
        guard wrapUps[taskID] == .interrupting, let runner = runners[taskID] else { return }
        wrapUps[taskID] = .awaitingSummary
        runner.send(Self.wrapUpMessage)
    }

    // MARK: - Helpers

    private func allTasks() -> [BunnyTask] {
        guard let context else { return [] }
        return (try? context.fetch(FetchDescriptor<BunnyTask>())) ?? []
    }

    private func task(with id: UUID) -> BunnyTask? {
        allTasks().first { $0.id == id }
    }

    private func didChangeState() {
        recomputeAttention()
        try? context?.save()
    }

    private func recomputeAttention(_ tasks: [BunnyTask]? = nil) {
        let count = (tasks ?? allTasks()).filter { $0.runState == .needsInput && $0.archivedAt == nil }.count
        if count != attentionCount {
            attentionCount = count
        }
    }

    private static func questionText(_ question: AgentQuestion) -> String {
        if question.kind == .approval {
            return question.approvalTitle ?? "Allow this action?"
        }
        return question.items.map(\.question).joined(separator: " / ")
    }

    private func notify(_ body: String, taskID: UUID) {
        let content = UNMutableNotificationContent()
        content.title = "Bunny"
        content.body = body
        content.sound = .default
        content.userInfo = ["taskID": taskID.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
