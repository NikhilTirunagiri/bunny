import Foundation

/// Runs `claude -p` in stream-json mode (see docs/superpowers/research/claude-stream-json.md).
final class ClaudeCodeRunner: AgentRunner {
    var onEvent: ((AgentEvent) -> Void)?
    private(set) var sessionID: String?

    private let options: AgentRunOptions
    private var process: AgentProcess?
    private var announcedSessionID: String?
    /// A user message was sent and its `result` has not arrived yet.
    private var turnInFlight = false
    private var terminationRequested = false
    private var didExit = false

    init(options: AgentRunOptions) {
        self.options = options
    }

    static func arguments(brief: AgentBrief, harness: AgentHarness, autonomy: AgentAutonomy, resumeSessionID: String?) -> [String] {
        let permissionMode = autonomy == .autonomous ? "bypassPermissions" : "acceptEdits"
        var arguments = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-prompt-tool", "stdio",
            "--permission-mode", permissionMode,
            "--append-system-prompt", AgentPromptBuilder.systemAppendix(for: harness),
        ]
        for directory in brief.extraDirectories {
            arguments += ["--add-dir", directory]
        }
        if let resumeSessionID {
            arguments += ["--resume", resumeSessionID]
        }
        return arguments
    }

    func start(brief: AgentBrief, harness: AgentHarness, resumeSessionID: String?, initialMessage: String?) {
        guard process == nil, !didExit else { return }
        sessionID = resumeSessionID

        let process = AgentProcess(
            executable: options.cliPath,
            arguments: Self.arguments(brief: brief, harness: harness, autonomy: options.autonomy, resumeSessionID: resumeSessionID),
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
        send(initialMessage ?? AgentPromptBuilder.prompt(for: brief, now: Date()))
    }

    func answer(_ question: AgentQuestion, with answer: AgentAnswer) {
        guard let requestID = question.requestID else {
            // No pending control request to reply to (e.g. a question from an earlier process).
            send(answer.summary(for: question))
            return
        }
        switch question.kind {
        case .approval:
            if answer.approved == true {
                process?.write(ClaudeWire.allow(requestID: requestID, updatedInput: question.rawInput ?? Data("{}".utf8)))
            } else {
                process?.write(ClaudeWire.deny(requestID: requestID, message: "The user declined."))
            }
        case .choices, .freeform:
            process?.write(ClaudeWire.allow(requestID: requestID, updatedInput: ClaudeWire.answeredInput(for: question, answer: answer)))
        }
    }

    func send(_ text: String) {
        guard let process, process.isRunning else { return }
        turnInFlight = true
        process.write(ClaudeWire.userMessage(text))
    }

    func interrupt() {
        process?.write(ClaudeWire.interrupt(requestID: AgentRunnerText.randomRequestID()))
    }

    func terminate() {
        guard let process, process.isRunning else { return }
        terminationRequested = true
        process.terminate()
    }

    // MARK: - Private

    private func handle(_ line: Data) {
        switch ClaudeWire.parse(line) {
        case let .initialized(id):
            sessionID = id
            if id != announcedSessionID {
                announcedSessionID = id
                emit(.sessionStarted(id))
            }
        case let .assistantText(text):
            let activity = AgentRunnerText.activityLine(text)
            if !activity.isEmpty {
                emit(.activity(activity))
            }
        case let .toolUse(name, summary):
            let detail = AgentRunnerText.activityLine(summary)
            emit(.activity(detail.isEmpty ? "Running \(name)…" : AgentRunnerText.truncated("Running \(name): \(detail)")))
        case let .permissionRequest(requestID, toolName, input):
            emit(.question(ClaudeWire.question(requestID: requestID, toolName: toolName, input: input)))
        case let .result(success, text, _):
            turnInFlight = false
            emit(.turnFinished(text: text, success: success))
        case .ignored:
            break
        }
    }

    private func handleExit(code: Int32, stderrTail: String) {
        guard !didExit else { return }
        didExit = true
        if turnInFlight && !terminationRequested {
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
