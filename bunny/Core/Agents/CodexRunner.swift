import Foundation

/// Runs `codex app-server --stdio` over JSON-RPC (see docs/superpowers/research/codex-app-server.md).
final class CodexRunner: AgentRunner {
    var onEvent: ((AgentEvent) -> Void)?
    private(set) var sessionID: String?

    private static let initializeID = 1
    private static let threadID = 2

    private let options: AgentRunOptions
    private var process: AgentProcess?
    private var launch: (brief: AgentBrief, harness: AgentHarness, resumeSessionID: String?, firstMessage: String)?
    private var nextRequestID = 3
    private var threadReady = false
    /// Messages waiting for the thread to exist or the running turn to finish; sent one turn at a time, in order.
    private var queuedMessages: [String] = []
    /// Request ids of `turn/start` calls whose response has not arrived yet.
    private var pendingTurnRequests: Set<Int> = []
    private var currentTurnID: String?
    private var lastCompletedTurnID: String?
    private var turnInFlight = false
    private var messageDelta = ""
    private var lastMessage = ""
    private var terminationRequested = false
    private var didExit = false

    init(options: AgentRunOptions) {
        self.options = options
    }

    func start(brief: AgentBrief, harness: AgentHarness, resumeSessionID: String?, initialMessage: String?) {
        guard process == nil, !didExit else { return }
        sessionID = resumeSessionID
        launch = (brief, harness, resumeSessionID, initialMessage ?? AgentPromptBuilder.prompt(for: brief, now: Date()))

        let process = AgentProcess(
            executable: options.cliPath,
            arguments: ["app-server", "--stdio"],
            cwd: brief.workingDirectory,
            environment: options.environment
        )
        process.onLine = { [weak self] line in self?.handle(line) }
        process.onExit = { [weak self] code, stderrTail in self?.handleExit(code: code, stderrTail: stderrTail) }

        do {
            try process.start()
        } catch {
            didExit = true
            emit(.failed(AgentRunnerText.launchFailure(harness: harness, path: options.cliPath, error: error)))
            emit(.exited(-1))
            return
        }
        self.process = process
        process.write(CodexWire.initialize(id: Self.initializeID))
    }

    func answer(_ question: AgentQuestion, with answer: AgentAnswer) {
        if question.kind == .approval, let rpcID = question.requestID {
            process?.write(CodexWire.approvalReply(rpcID: rpcID, approved: answer.approved == true))
        } else {
            // Marker questions end the turn; the answer becomes the next turn.
            send(answer.summary(for: question))
        }
    }

    /// Starts a new turn, or queues `text` until the thread exists / the running turn completes.
    func send(_ text: String) {
        guard let process, process.isRunning else { return }
        queuedMessages.append(text)
        startNextQueuedTurn()
    }

    func interrupt() {
        guard let process, threadReady, let threadID = sessionID, let turnID = currentTurnID else { return }
        process.write(CodexWire.turnInterrupt(id: takeRequestID(), threadID: threadID, turnID: turnID))
    }

    func terminate() {
        guard let process, process.isRunning else { return }
        terminationRequested = true
        process.terminate()
    }

    func processForShutdown() -> AgentProcess? {
        guard let process else { return nil }
        terminationRequested = true
        return process
    }

    // MARK: - Private

    private func startNextQueuedTurn() {
        guard threadReady, !turnInFlight, let threadID = sessionID, let process, !queuedMessages.isEmpty else { return }
        let text = queuedMessages.removeFirst()
        let id = takeRequestID()
        pendingTurnRequests.insert(id)
        turnInFlight = true
        currentTurnID = nil
        messageDelta = ""
        lastMessage = ""
        process.write(CodexWire.turnStart(id: id, threadID: threadID, text: text, effort: options.effort))
    }

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func handle(_ line: Data) {
        switch CodexWire.parse(line) {
        case let .response(id, threadID, turnID, error):
            handleResponse(id: id, threadID: threadID, turnID: turnID, error: error)
        case let .turnStarted(turnID):
            currentTurnID = turnID
        case let .agentMessageDelta(delta):
            messageDelta += delta
        case let .agentMessage(text):
            lastMessage = text
            messageDelta = ""
            let activity = AgentRunnerText.activityLine(text)
            if !activity.isEmpty {
                emit(.activity(activity))
            }
        case let .commandStarted(command):
            emit(.activity(AgentRunnerText.truncated("Running \(AgentRunnerText.activityLine(command))")))
        case let .turnCompleted(turnID, status, error):
            handleTurnCompleted(turnID: turnID, status: status, error: error)
        case let .approvalRequest(rpcID, method, title, detail):
            emit(.question(AgentQuestion(
                kind: .approval,
                items: [],
                approvalTitle: title,
                approvalDetail: detail,
                requestID: rpcID,
                method: method,
                rawInput: nil
            )))
        case let .mcpElicitation(rpcID, serverName):
            if serverName == BunnyToolsEndpoint.serverName, options.tools != nil {
                // Codex's approval prompt for a Bunny tool call (seen under "on-request"). Bunny tools this
                // run attached are always allowed, like Claude's `--allowedTools mcp__bunny`; a "bunny"
                // server from elsewhere (no tools on this run) is not.
                process?.write(CodexWire.elicitationReply(rpcID: rpcID, accept: true))
            } else {
                process?.write(CodexWire.methodNotFound(rpcID: rpcID))
            }
        case let .unsupportedRequest(rpcID):
            process?.write(CodexWire.methodNotFound(rpcID: rpcID))
        case .ignored:
            break
        }
    }

    private func handleResponse(id: Int, threadID: String?, turnID: String?, error: String?) {
        switch id {
        case Self.initializeID:
            if let error {
                failAndShutDown(error)
                return
            }
            guard let launch else { return }
            process?.write(CodexWire.initialized())
            if let resumeSessionID = launch.resumeSessionID {
                process?.write(CodexWire.threadResume(
                    id: Self.threadID,
                    threadID: resumeSessionID,
                    model: options.model,
                    tools: options.tools
                ))
            } else {
                process?.write(CodexWire.threadStart(
                    id: Self.threadID,
                    cwd: launch.brief.workingDirectory,
                    approvalPolicy: options.autonomy == .autonomous ? "never" : "on-request",
                    sandbox: "workspace-write",
                    developerInstructions: AgentPromptBuilder.systemAppendix(for: launch.harness, toolsAvailable: options.tools != nil),
                    writableRoots: launch.brief.extraDirectories,
                    model: options.model,
                    tools: options.tools
                ))
            }

        case Self.threadID:
            guard let launch else { return }
            guard error == nil, let resolvedID = threadID ?? launch.resumeSessionID else {
                failAndShutDown(error ?? "Codex did not return a thread id")
                return
            }
            sessionID = resolvedID
            threadReady = true
            emit(.sessionStarted(resolvedID))
            queuedMessages.insert(launch.firstMessage, at: 0)
            startNextQueuedTurn()

        default:
            guard pendingTurnRequests.remove(id) != nil else { return }
            if let error {
                turnInFlight = false
                emit(.turnFinished(text: error, success: false))
                startNextQueuedTurn()
            } else if let turnID {
                currentTurnID = turnID
            }
        }
    }

    private func handleTurnCompleted(turnID: String?, status: String, error: String?) {
        // Only the running turn's completion counts; drop duplicates and stale turns.
        guard turnInFlight else { return }
        if let turnID {
            if let currentTurnID, turnID != currentTurnID { return }
            if turnID == lastCompletedTurnID { return }
            lastCompletedTurnID = turnID
        }
        turnInFlight = false
        currentTurnID = nil
        defer { startNextQueuedTurn() }
        let message = lastMessage.isEmpty ? messageDelta : lastMessage
        messageDelta = ""
        switch status {
        case "completed":
            if let question = AgentMarkers.extractQuestion(from: message).question {
                emit(.question(question))
            } else {
                emit(.turnFinished(text: message, success: true))
            }
        case "failed":
            emit(.turnFinished(text: error ?? "Codex turn failed", success: false))
        case "interrupted":
            emit(.turnFinished(text: "Interrupted", success: false))
        default:
            emit(.turnFinished(text: error ?? "Codex turn ended with status \(status)", success: false))
        }
    }

    /// A handshake step failed: report it and stop the server so the task doesn't sit in `running`.
    private func failAndShutDown(_ message: String) {
        guard !didExit else { return }
        emit(.failed(message))
        // The failure is already reported; the exit that follows only needs `exited`.
        terminationRequested = true
        process?.terminate()
    }

    private func handleExit(code: Int32, stderrTail: String) {
        guard !didExit else { return }
        didExit = true
        let unfinished = !threadReady || turnInFlight
        if unfinished && !terminationRequested {
            emit(.failed(AgentRunnerText.exitFailure(code: code, stderrTail: stderrTail)))
        }
        turnInFlight = false
        emit(.exited(code))
    }

    private func emit(_ event: AgentEvent) {
        DispatchQueue.main.async {
            self.onEvent?(event)
        }
    }
}
