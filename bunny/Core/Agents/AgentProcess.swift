import Foundation

/// Plain `Error` (not `LocalizedError`): in the app target this type is implicitly `@MainActor`,
/// which cannot satisfy `LocalizedError`'s nonisolated requirements. Use `message` instead.
enum AgentProcessError: Error, Equatable {
    case notExecutable(String)
    case missingWorkingDirectory(String)
    case launchFailed(String)

    var message: String {
        switch self {
        case let .notExecutable(path): return "No executable found at \(path)"
        case let .missingWorkingDirectory(path): return "Working directory \(path) does not exist"
        case let .launchFailed(message): return message
        }
    }
}

/// A child process speaking newline-delimited JSON over stdin/stdout.
///
/// Threading: only raw pipe reads, the termination handler and stdin writes run off the main
/// thread, and those closures touch nothing but Foundation objects. Every chunk is handed to the
/// main queue, where all state lives, lines are split and `onLine` / `onExit` are called. Keeping
/// the logic on main is what makes this correct both under SwiftPM (nonisolated) and in the app
/// target, where Core types are implicitly `@MainActor`. Use an instance from the main thread only.
final class AgentProcess {
    /// stdout JSON lines (without the newline). Delivered on the main queue.
    var onLine: ((Data) -> Void)?
    /// Exit code (or terminating signal number) + stderr tail (last 4 KB, UTF-8 lossy, trimmed). Delivered once, on the main queue, after all stdout lines.
    var onExit: ((Int32, String) -> Void)?

    private static let stderrCapacity = 64 * 1024
    private static let stderrTailLength = 4 * 1024
    /// How long to wait for stdout/stderr EOF after the process exited (a grandchild may hold the pipes open).
    private static let drainGrace: TimeInterval = 1
    private static let killGrace: TimeInterval = 3

    private let executable: String
    private let arguments: [String]
    private let cwd: String
    private let environment: [String: String]

    private let process = Process()
    private let stdinPipe = Pipe()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let writeQueue = DispatchQueue(label: "bunny.agent-process.stdin")

    private var lineBuffer = JSONLineBuffer()
    private var stderrBuffer = Data()
    private var started = false
    private var stdoutClosed = false
    private var stderrClosed = false
    private var terminationStatus: Int32?
    private var didExit = false

    init(executable: String, arguments: [String], cwd: String, environment: [String: String]) {
        self.executable = executable
        self.arguments = arguments
        self.cwd = cwd
        self.environment = environment
    }

    var isRunning: Bool {
        started && !didExit && process.isRunning
    }

    /// Throws if the executable is missing/not executable, the working directory is missing, or launching fails.
    func start() throws {
        guard !started else { return }
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: executable, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isExecutableFile(atPath: executable) else {
            throw AgentProcessError.notExecutable(executable)
        }
        guard fileManager.fileExists(atPath: cwd, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw AgentProcessError.missingWorkingDirectory(cwd)
        }

        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.environment = environment
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // A write to a pipe whose reader died must fail with EPIPE instead of killing Bunny.
        _ = fcntl(stdinPipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        // These run on Foundation's background threads: read, then hop to main. They capture self
        // strongly so the exit is always delivered; finish() drops them, breaking the cycle.
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { self.receiveStdout(data) }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { self.receiveStderr(data) }
        }
        process.terminationHandler = { process in
            let status = process.terminationStatus
            DispatchQueue.main.async { self.receiveTermination(status) }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            process.terminationHandler = nil
            throw AgentProcessError.launchFailed(error.localizedDescription)
        }
        // Process closes the parent's copies of the child-side pipe ends itself, so EOF propagates.
        started = true
    }

    /// Writes `line` + "\n" to stdin. No-op before start and after exit.
    func write(_ line: Data) {
        guard started, !didExit else { return }
        let payload = line + Data([0x0A])
        let handle = stdinPipe.fileHandleForWriting
        writeQueue.async {
            // Throws (EPIPE) if the child already closed stdin; nothing useful to do then.
            try? handle.write(contentsOf: payload)
        }
    }

    /// SIGTERM, then SIGKILL after 3 s if still running.
    func terminate() {
        guard started, !didExit, process.isRunning else { return }
        process.terminate()
        let process = self.process
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.killGrace) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    // MARK: - Main-queue handlers

    private func receiveStdout(_ data: Data) {
        guard !didExit else { return }
        if data.isEmpty {
            stdoutClosed = true
            finishIfDrained()
            return
        }
        for line in lineBuffer.append(data) {
            onLine?(line)
        }
    }

    private func receiveStderr(_ data: Data) {
        guard !didExit else { return }
        if data.isEmpty {
            stderrClosed = true
            finishIfDrained()
            return
        }
        stderrBuffer.append(data)
        if stderrBuffer.count > Self.stderrCapacity {
            stderrBuffer = Data(stderrBuffer.suffix(Self.stderrCapacity))
        }
    }

    private func receiveTermination(_ status: Int32) {
        guard !didExit, terminationStatus == nil else { return }
        terminationStatus = status
        finishIfDrained()
        if !didExit {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.drainGrace) {
                self.finish()
            }
        }
    }

    private func finishIfDrained() {
        if terminationStatus != nil, stdoutClosed, stderrClosed {
            finish()
        }
    }

    private func finish() {
        guard !didExit, let status = terminationStatus else { return }
        didExit = true
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        let stdinHandle = stdinPipe.fileHandleForWriting
        writeQueue.async { try? stdinHandle.close() }

        let tail = String(decoding: stderrBuffer.suffix(Self.stderrTailLength), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let onExit = self.onExit
        onLine = nil
        self.onExit = nil
        onExit?(status, tail)
    }
}
