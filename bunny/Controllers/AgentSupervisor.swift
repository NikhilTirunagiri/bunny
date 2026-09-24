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
    /// so events from a retired runner are ignored (except its `exited`, see `terminating`).
    private var runners: [UUID: AgentRunner] = [:]

    /// Runs being prepared off the main thread (CLI detection, login-shell environment), not yet started.
    private var pendingLaunches: [UUID: PendingLaunch] = [:]

    private struct PendingLaunch {
        let token = UUID()
        let harness: AgentHarness
        let brief: AgentBrief
        let resumeSessionID: String?
        let initialMessage: String?
        /// Resume-with-answer only: the question to restore if the CLI turns out to be missing.
        let restoreQuestion: Data?
    }

    private enum WrapUpPhase: Equatable {
        /// Timer expired: the turn was interrupted; the wrap-up message has not been sent yet.
        case interrupting
        /// The wrap-up message was sent; its reply is the summary. `interruptedTurnSeen` is false when the
        /// message went out on the 1 s fallback, before the interrupted turn reported its (failed) end.
        case awaitingSummary(interruptedTurnSeen: Bool)
    }

    @ObservationIgnored private var modelContainer: ModelContainer?
    /// Retired runners whose process may still be alive (stop's grace period, handoff), until `exited`.
    /// `shutdownAll` terminates these too.
    @ObservationIgnored private var terminating: [ObjectIdentifier: AgentRunner] = [:]
    /// Actions waiting for a retired runner's `exited` (or a timeout), keyed like `terminating`.
    @ObservationIgnored private var exitWaiters: [ObjectIdentifier: (token: UUID, action: () -> Void)] = [:]
    @ObservationIgnored private var wrapUps: [UUID: WrapUpPhase] = [:]
    /// Subtask ids in the order they were numbered in the brief (for `<bunny-subtasks-done>`).
    @ObservationIgnored private var briefSubtaskIDs: [UUID: [UUID]] = [:]
    /// Tasks whose timer was already seen expired, so an expiry is acted on once, when it flips.
    @ObservationIgnored private var expiredTimers: Set<UUID> = []
    @ObservationIgnored private var checkTimer: Timer?
    /// Tasks whose session is being opened (the ≤2 s handoff wait plus the launch itself):
    /// repeated opens are ignored until it finishes, so a session is never launched twice.
    @ObservationIgnored private var pendingHandoffs: Set<UUID> = []

    private static let wrapUpMessage = "Time's up — stop here and reply with a summary of what's done and what's left."
    private static let timeRanOutSuffix = " · Time ran out"
    private static let handoffExitTimeout: TimeInterval = 2
    private static let stopGracePeriod: TimeInterval = 3

    private var context: ModelContext? { modelContainer?.mainContext }

    // MARK: - Setup

    /// Called once from AppDelegate. Recovers runs interrupted by quitting Bunny (spec §7).
    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        AgentSettings.warmUp()

        let all = (try? modelContainer.mainContext.fetch(FetchDescriptor<BunnyTask>())) ?? []
        for task in all {
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

    /// Called when Bunny quits: terminates every agent process, live or still in its grace period.
    /// Running tasks become `stopped` (as launch recovery would); `needsInput` stays so answering resumes.
    func shutdownAll() {
        checkTimer?.invalidate()
        checkTimer = nil
        let live = runners
        runners.removeAll()
        pendingLaunches.removeAll()
        wrapUps.removeAll()
        exitWaiters.removeAll()
        pendingHandoffs.removeAll()
        // Synchronous: the app is about to exit, so terminate()'s delayed SIGKILL would never run.
        for runner in terminating.values {
            runner.terminateNow()
        }
        terminating.removeAll()
        for (taskID, runner) in live {
            runner.terminateNow()
            if let task = task(with: taskID), task.runState == .running {
                task.runState = .stopped
                task.agentActivity = "Interrupted — Bunny quit"
                task.agentFinishedAt = Date()
            }
        }
        try? context?.save()
    }

    // MARK: - Queries

    /// A runner is running for the task, or one is being prepared.
    func isLive(_ taskID: UUID) -> Bool {
        runners[taskID] != nil || pendingLaunches[taskID] != nil
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
        guard context != nil, !task.runState.isActive, !isLive(task.id) else { return }
        let harness = harness ?? AgentSettings.defaultHarness

        // A set but unusable path fails right away; an unset one is detected off the main thread below.
        let cliPath = AgentSettings.cliPath(for: harness)
        if !cliPath.isEmpty && !Self.isExecutableFile(cliPath) {
            // Keeps any previous harness/session pair intact, so that session can still be opened.
            failMissingCLI(task, harness: harness)
            return
        }

        wrapUps[task.id] = nil
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

        prepareLaunch(task.id, PendingLaunch(harness: harness, brief: brief, resumeSessionID: nil,
                                             initialMessage: nil, restoreQuestion: nil))
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
        guard pendingLaunches[task.id] == nil else { return }

        // No live runner (Bunny was restarted, or the process exited). The persisted question's request id
        // belonged to the dead process, so never `runner.answer` it: resume the session with the answer as text.
        let harness = task.harness ?? AgentSettings.defaultHarness
        let cliPath = AgentSettings.cliPath(for: harness)
        if !cliPath.isEmpty && !Self.isExecutableFile(cliPath) {
            // Keep the question so the owner can answer again after fixing the path.
            task.agentActivity = Self.missingCLIMessage(harness)
            didChangeState()
            return
        }

        let brief = makeBrief(for: task, workingDirectory: task.agentWorkingDirectory)
        let resumeMessage = "Answer to your earlier question \"\(Self.questionText(question))\": \(answer.summary(for: question))"
        let savedQuestion = task.agentQuestionData

        task.agentHarness = harness.rawValue
        task.agentWorkingDirectory = brief.workingDirectory
        task.runState = .running
        task.agentQuestionData = nil
        task.agentFinishedAt = nil
        task.agentActivity = "Resuming…"
        didChangeState()

        let request: PendingLaunch
        if let sessionID = task.agentSessionID {
            request = PendingLaunch(harness: harness, brief: brief, resumeSessionID: sessionID,
                                    initialMessage: resumeMessage, restoreQuestion: savedQuestion)
        } else {
            // No session to resume: start over with the brief plus the answer.
            let prompt = AgentPromptBuilder.prompt(for: brief, now: Date()) + "\n\n" + resumeMessage
            request = PendingLaunch(harness: harness, brief: brief, resumeSessionID: nil,
                                    initialMessage: prompt, restoreQuestion: savedQuestion)
        }
        prepareLaunch(task.id, request)
    }

    /// Interrupt, then terminate after 3 s (so the CLI can save the session). State `stopped`.
    func stop(_ task: BunnyTask) {
        pendingLaunches[task.id] = nil
        if let runner = runners.removeValue(forKey: task.id) {
            retire(runner, interruptFirst: true)
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
            if task.runState.isActive {
                // Running but the CLI hasn't reported its session yet: nothing to open, and never a second run.
                task.agentActivity = "Still starting…"
            } else {
                start(task, harness: nil)
            }
            return
        }
        let harness = task.harness ?? AgentSettings.defaultHarness
        let taskID = task.id
        guard pendingHandoffs.insert(taskID).inserted else { return }

        if task.runState.isActive {
            // One process per session: stop the background one, and open the app only once it has exited.
            pendingLaunches[taskID] = nil
            wrapUps[taskID] = nil
            task.runState = .handedOff
            task.agentQuestionData = nil
            task.agentFinishedAt = Date()
            task.agentActivity = "Opening…"
            didChangeState()
            if let runner = runners.removeValue(forKey: taskID) {
                retire(runner, interruptFirst: false)
                whenExited(runner, timeout: Self.handoffExitTimeout) { [weak self] in
                    self?.launchSession(taskID, harness: harness, sessionID: sessionID)
                }
                return
            }
        }
        launchSession(taskID, harness: harness, sessionID: sessionID)
    }

    /// Resets the agent fields of a task that isn't running an agent.
    func clear(_ task: BunnyTask) {
        guard !task.runState.isActive else { return }
        pendingLaunches[task.id] = nil
        if let runner = runners.removeValue(forKey: task.id) {
            retire(runner, interruptFirst: false)
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
        } else {
            pendingLaunches[taskID] = nil
            wrapUps[taskID] = nil
            if let runner = runners.removeValue(forKey: taskID) {
                retire(runner, interruptFirst: false)
            }
        }
        briefSubtaskIDs[taskID] = nil
        expiredTimers.remove(taskID)
    }

    // MARK: - Launch

    /// Keeps the task in its "Starting…"/"Resuming…" running state while the CLI path (if unset) and the
    /// login-shell environment are resolved off the main thread, then starts the runner on main.
    private func prepareLaunch(_ taskID: UUID, _ request: PendingLaunch) {
        pendingLaunches[taskID] = request
        let token = request.token
        if AgentSettings.cliPath(for: request.harness).isEmpty {
            AgentSettings.detect(request.harness) { [weak self] _ in
                self?.resolveEnvironment(taskID, token: token)
            }
        } else {
            resolveEnvironment(taskID, token: token)
        }
    }

    private func resolveEnvironment(_ taskID: UUID, token: UUID) {
        guard pendingLaunches[taskID]?.token == token else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let environment = ShellEnvironment.environment()
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.completeLaunch(taskID, token: token, environment: environment)
                }
            }
        }
    }

    private func completeLaunch(_ taskID: UUID, token: UUID, environment: [String: String]) {
        // Stopped, handed off, cleared or replaced meanwhile → drop this launch.
        guard let request = pendingLaunches[taskID], request.token == token else { return }
        pendingLaunches[taskID] = nil
        guard let task = task(with: taskID), task.runState == .running, runners[taskID] == nil else { return }

        let cliPath = AgentSettings.cliPath(for: request.harness)
        guard Self.isExecutableFile(cliPath) else {
            if let question = request.restoreQuestion {
                task.runState = .needsInput
                task.agentQuestionData = question
                task.agentActivity = Self.missingCLIMessage(request.harness)
                didChangeState()
            } else {
                failMissingCLI(task, harness: request.harness)
            }
            return
        }

        let options = AgentRunOptions(cliPath: cliPath, autonomy: AgentSettings.autonomy, environment: environment)
        let runner: AgentRunner
        switch request.harness {
        case .claudeCode: runner = ClaudeCodeRunner(options: options)
        case .codex: runner = CodexRunner(options: options)
        }

        runners[taskID] = runner
        // The task id is captured, so two concurrent runs never cross wires.
        runner.onEvent = { [weak self, weak runner] event in
            guard let self, let runner else { return }
            self.handle(event, taskID: taskID, from: runner)
        }
        runner.start(brief: request.brief, harness: request.harness,
                     resumeSessionID: request.resumeSessionID, initialMessage: request.initialMessage)
    }

    /// Opens the session in the owner's app and records which app was actually used (or the fallback text).
    /// Ends the task's `pendingHandoffs` entry once the launch has completed.
    private func launchSession(_ taskID: UUID, harness: AgentHarness, sessionID: String) {
        guard let task = task(with: taskID) else {
            pendingHandoffs.remove(taskID)
            return
        }
        let cwd = task.agentWorkingDirectory ?? AgentSettings.defaultWorkspace
        Task { @MainActor [weak self] in
            let outcome = await SessionLauncher.open(harness: harness, sessionID: sessionID, cwd: cwd)
            self?.pendingHandoffs.remove(taskID)
            guard let self, let task = self.task(with: taskID), !task.runState.isActive else { return }
            task.agentActivity = outcome.activityText
            self.didChangeState()
        }
    }

    /// Takes a runner out of service. It stays in `terminating` (reachable by `shutdownAll`) until it exits.
    private func retire(_ runner: AgentRunner, interruptFirst: Bool) {
        terminating[ObjectIdentifier(runner)] = runner
        if interruptFirst {
            runner.interrupt()
            let grace = Self.stopGracePeriod
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(grace))
                runner.terminate()
            }
        } else {
            runner.terminate()
        }
    }

    /// Runs `action` once, when the retired `runner` reports `exited` or after `timeout`, whichever is first.
    private func whenExited(_ runner: AgentRunner, timeout: TimeInterval, _ action: @escaping () -> Void) {
        let key = ObjectIdentifier(runner)
        let token = UUID()
        exitWaiters[key] = (token, action)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.fireExitWaiter(key, token: token)
        }
    }

    /// `token` nil = the runner exited; otherwise only the waiter registered with that token fires.
    private func fireExitWaiter(_ key: ObjectIdentifier, token: UUID?) {
        guard let waiter = exitWaiters[key], token == nil || waiter.token == token else { return }
        exitWaiters[key] = nil
        waiter.action()
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    private static func missingCLIMessage(_ harness: AgentHarness) -> String {
        "\(harness.displayName) not found — set its path in Settings → Agents."
    }

    private func failMissingCLI(_ task: BunnyTask, harness: AgentHarness) {
        task.runState = .failed
        task.agentSummary = Self.missingCLIMessage(harness)
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

    /// Non-archived children in list order (`sortOrder`, then `createdAt`) — the brief's numbering.
    private func subtasks(of task: BunnyTask) -> [BunnyTask] {
        guard let context else { return [] }
        let parentID: UUID? = task.id
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.parentID == parentID && $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Events

    private func handle(_ event: AgentEvent, taskID: UUID, from runner: AgentRunner) {
        let key = ObjectIdentifier(runner)
        if terminating[key] != nil {
            // A retired runner: only its exit matters (it may unblock a handoff).
            if case .exited = event {
                terminating[key] = nil
                fireExitWaiter(key, token: nil)
            }
            return
        }
        // Ignore events from a runner that isn't the task's current one.
        guard let current = runners[taskID], current === runner else { return }
        guard let task = task(with: taskID) else {
            runners[taskID] = nil
            retire(runner, interruptFirst: false)
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
            switch wrapUps[taskID] {
            case .interrupting?:
                // The interrupted turn ended: keep the runner and ask for the wrap-up summary now.
                sendWrapUp(taskID, interruptedTurnSeen: true)
                return
            case .awaitingSummary(interruptedTurnSeen: false)? where !success:
                // The interrupted turn's own end, arriving after the 1 s fallback send: the summary is still to come.
                wrapUps[taskID] = .awaitingSummary(interruptedTurnSeen: true)
                return
            default:
                break
            }
            finishTurn(task, text: text, success: success)
            // One turn per handoff: follow-ups resume the session in a new process.
            runners[taskID] = nil
            retire(runner, interruptFirst: false)

        case let .failed(message):
            wrapUps[taskID] = nil
            task.runState = .failed
            task.agentSummary = message
            task.agentQuestionData = nil
            task.agentFinishedAt = Date()
            runners[taskID] = nil
            retire(runner, interruptFirst: false)

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
        let phase = wrapUps.removeValue(forKey: task.id)
        if case .awaitingSummary? = phase {
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

        let current = subtasks(of: task)
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = (briefSubtaskIDs[task.id] ?? current.map(\.id)).compactMap { byID[$0] }
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
        guard let context else { return }
        // Also picks up archives/deletions made elsewhere (only a needsInput task can be counted).
        if attentionCount > 0 {
            recomputeAttention()
        }
        // Timer expiry only matters for active runs; skip the fetch when there are none.
        guard !runners.isEmpty || attentionCount > 0 else { return }

        let running = AgentRunState.running.rawValue
        let needsInput = AgentRunState.needsInput.rawValue
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.timerDuration != nil && ($0.agentState == running || $0.agentState == needsInput) }
        )
        let tasks = (try? context.fetch(descriptor)) ?? []
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
                    self?.sendWrapUp(taskID, interruptedTurnSeen: false)
                }
            case .needsInput:
                if !task.agentActivity.hasSuffix(Self.timeRanOutSuffix) {
                    task.agentActivity += Self.timeRanOutSuffix
                }
            default:
                break
            }
        }
    }

    /// Sends the wrap-up request once: when the interrupted turn ends, or 1 s after the interrupt.
    private func sendWrapUp(_ taskID: UUID, interruptedTurnSeen: Bool) {
        guard wrapUps[taskID] == .interrupting, let runner = runners[taskID] else { return }
        wrapUps[taskID] = .awaitingSummary(interruptedTurnSeen: interruptedTurnSeen)
        runner.send(Self.wrapUpMessage)
    }

    // MARK: - Helpers

    private func task(with id: UUID) -> BunnyTask? {
        guard let context else { return nil }
        var descriptor = FetchDescriptor<BunnyTask>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func didChangeState() {
        recomputeAttention()
        try? context?.save()
    }

    private func recomputeAttention() {
        guard let context else { return }
        let needsInput = AgentRunState.needsInput.rawValue
        let descriptor = FetchDescriptor<BunnyTask>(
            predicate: #Predicate { $0.agentState == needsInput && $0.archivedAt == nil }
        )
        let count = (try? context.fetchCount(descriptor)) ?? attentionCount
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
