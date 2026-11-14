import AppKit
import Foundation
import os

/// What `SessionLauncher.open` ended up doing.
enum SessionLaunchOutcome: Equatable {
    /// The session was opened in the app of this name (the chosen one, or Terminal as the fallback,
    /// with a one-line `note` saying why).
    case opened(String, note: String?)
    /// Nothing could be opened; the resume command was copied to the pasteboard. The text explains it for the panel.
    case copiedToPasteboard(String)

    /// The task's activity: "Opened in <app>", and the note on a second line (`AgentPanelRules.openedNote`).
    var activityText: String {
        switch self {
        case let .opened(name, note): return "Opened in \(name)" + (note.map { "\n\($0)" } ?? "")
        case let .copiedToPasteboard(text): return text
        }
    }
}

/// Executes `SessionLaunchPlanner` steps to open an agent session in the owner's preferred app.
@MainActor
enum SessionLauncher {
    private static let log = Logger(subsystem: "bunny", category: "SessionLauncher")
    private static let commandFileLifetime: TimeInterval = 60
    /// `claude --desktop` only hands the session to the app; it is given this long to do so.
    private static let cliTimeout: TimeInterval = 30
    /// `/usr/bin/open` answers at once; if it ever does not, the launch must still end.
    private static let openTimeout: TimeInterval = 15
    private static let killGrace: TimeInterval = 2

    private struct LaunchError: Error {
        let message: String
        /// What the tool itself said (the first meaningful line of its output), for the note in the agent section.
        var said: String?
    }

    /// Executes SessionLaunchPlanner steps for the agent's chosen app; on failure falls back to the Terminal plan
    /// (with a note); last resort copies the resume command to the pasteboard. Waits for `/usr/bin/open` to report
    /// success before calling it opened.
    /// `model`/`effort`: the run's settings, passed on to the resume command (nil = the CLI's default).
    static func open(harness: AgentHarness, sessionID: String, cwd: String,
                     model: String? = nil, effort: String? = nil) async -> SessionLaunchOutcome {
        let cliPath = AgentSettings.cliPath(for: harness)
        guard !cliPath.isEmpty, FileManager.default.isExecutableFile(atPath: cliPath) else {
            // Opening a terminal on `exec ''` would just fail there. Hand over a command that works in a login shell.
            let command = SessionLaunchPlanner.resumeCommand(
                harness: harness, cliPath: AgentSettings.commandName(for: harness), sessionID: sessionID, cwd: cwd,
                model: model, effort: effort)
            copyToPasteboard(command)
            return .copiedToPasteboard(
                "\(harness.displayName) not found — set its path in Settings → Agents. Resume command copied: \(command)")
        }

        let terminal = OpenInApp.terminal.displayName
        let target = AgentSettings.openTarget(for: harness)
        var note: String?
        if target.app != .terminal {
            if let appPath = target.appPath {
                let steps = SessionLaunchPlanner.plan(app: target.app, harness: harness, cliPath: cliPath,
                                                      sessionID: sessionID, cwd: cwd, model: model, effort: effort,
                                                      appPath: appPath, bundleIdentifier: target.bundleIdentifier)
                do {
                    try await execute(steps)
                    return .opened(target.name, note: nil)
                } catch {
                    logFailure(target.name, error)
                    let said = (error as? LaunchError)?.said
                    note = "Couldn't open in \(target.name)\(said.map { " (\($0))" } ?? "") — opened in \(terminal) instead."
                }
            } else {
                logFailure(target.name, LaunchError(message: "not installed"))
                note = "\(target.name) wasn't found — opened in \(terminal) instead."
            }
        }

        let terminalSteps = SessionLaunchPlanner.plan(app: .terminal, harness: harness, cliPath: cliPath,
                                                      sessionID: sessionID, cwd: cwd, model: model, effort: effort)
        do {
            try await execute(terminalSteps)
            return .opened(terminal, note: note)
        } catch {
            logFailure(terminal, error)
        }

        let command = SessionLaunchPlanner.resumeCommand(harness: harness, cliPath: cliPath, sessionID: sessionID,
                                                         cwd: cwd, model: model, effort: effort)
        copyToPasteboard(command)
        return .copiedToPasteboard("Couldn't open the app — resume command copied: \(command)")
    }

    private static func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    private static func logFailure(_ target: String, _ error: Error) {
        let reason = (error as? LaunchError)?.message ?? String(describing: error)
        log.error("Opening \(target, privacy: .public) failed: \(reason, privacy: .public)")
    }

    // MARK: - Steps

    private static func execute(_ steps: [LaunchStep]) async throws {
        // Check what can be checked up front, so a failure falls back before anything was opened.
        for step in steps {
            try preflight(step)
        }
        for step in steps {
            switch step {
            case let .runCommandFile(script, openArguments):
                try await runCommandFile(script, openArguments: openArguments)
            case let .runCLI(executable, arguments, cwd):
                try await runCLI(executable, arguments, cwd: cwd)
            case let .exec(executable, arguments):
                try await exec(executable, arguments)
            case let .openURL(string, delay):
                // preflight validated the URL and that an app handles its scheme.
                guard let url = URL(string: string) else { continue }
                guard delay > 0 else {
                    guard NSWorkspace.shared.open(url) else {
                        throw LaunchError(message: "NSWorkspace.open(\(string)) returned false")
                    }
                    continue
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    if !NSWorkspace.shared.open(url) {
                        logFailure(string, LaunchError(message: "NSWorkspace.open returned false"))
                    }
                }
            }
        }
    }

    private static func preflight(_ step: LaunchStep) throws {
        switch step {
        case .runCommandFile:
            break
        case let .exec(executable, _), let .runCLI(executable, _, _):
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw LaunchError(message: "No executable at \(executable)")
            }
        case let .openURL(string, _):
            guard let url = URL(string: string) else {
                throw LaunchError(message: "Invalid URL \(string)")
            }
            guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else {
                throw LaunchError(message: "No app handles \(url.scheme ?? string)")
            }
        }
    }

    /// `/usr/bin/open` exits promptly, so its status is awaited and a non-zero exit (e.g. app missing) throws.
    /// Editor CLIs are only launched: they may stay attached to the editor for a while.
    private static func exec(_ executable: String, _ arguments: [String]) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        // `open` hands its environment to an app it launches; an editor CLI to the editor.
        process.environment = ShellEnvironment.inherited()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        guard executable == "/usr/bin/open" else {
            try process.run()
            return
        }
        guard let status = try await run(process, timeout: openTimeout) else {
            throw LaunchError(message: "open \(arguments.joined(separator: " ")) did not finish in \(Int(openTimeout)) s")
        }
        guard status == 0 else {
            throw LaunchError(message: "open \(arguments.joined(separator: " ")) exited with status \(status)")
        }
    }

    /// Starts `process` and waits for it without blocking the main thread. Returns its exit status,
    /// or nil when it had not exited after `timeout` and was killed: SIGTERM to its process group
    /// (`Process` makes the child the leader of its own), SIGKILL after `killGrace`.
    private static func run(_ process: Process, timeout: TimeInterval) async throws -> Int32? {
        let timedOut = OSAllocatedUnfairLock(initialState: false)
        let grace = killGrace
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
                return
            }
            let pid = process.processIdentifier
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                timedOut.withLock { $0 = true }
                if kill(-pid, SIGTERM) != 0 { kill(pid, SIGTERM) }
                DispatchQueue.global().asyncAfter(deadline: .now() + grace) {
                    guard process.isRunning else { return }
                    if kill(-pid, SIGKILL) != 0 { kill(pid, SIGKILL) }
                }
            }
        }
        return timedOut.withLock { $0 } ? nil : status
    }

    /// Runs a short-lived command in `cwd` with the scrubbed environment and waits for it. Success is
    /// exit status 0 and nothing else: what it prints is not judged (under a pseudo-terminal the
    /// output carries control characters). A non-zero exit, or no exit within `cliTimeout`, throws,
    /// with the first meaningful line of the output as `said`.
    private static func runCLI(_ executable: String, _ arguments: [String], cwd: String) async throws {
        // May run a login shell (≤3 s) when the PATH is not cached yet: never on the main thread.
        let environment = await Task.detached { ShellEnvironment.environment() }.value
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        // Output goes to a file, not a pipe: a pipe read could wait on a process the command left behind.
        let outputFile = FileManager.default.temporaryDirectory.appendingPathComponent("bunny-open-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: outputFile.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputFile) else {
            throw LaunchError(message: "Couldn't create \(outputFile.path)")
        }
        defer {
            try? output.close()
            try? FileManager.default.removeItem(at: outputFile)
        }
        process.standardOutput = output
        process.standardError = output

        let command = "\(executable) \(arguments.joined(separator: " "))"
        guard let status = try await run(process, timeout: cliTimeout) else {
            throw LaunchError(message: "\(command) did not finish in \(Int(cliTimeout)) s",
                              said: "no answer after \(Int(cliTimeout)) s")
        }
        guard status != 0 else { return }
        let printed = (try? Data(contentsOf: outputFile)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        throw LaunchError(message: "\(command) exited with status \(status): \(printed)",
                          said: SessionLaunchPlanner.firstMeaningfulLine(printed))
    }

    /// Writes `~/Library/Application Support/Bunny/launch/<uuid>.command` (0755), runs `/usr/bin/open` with
    /// `openArguments` (the placeholder argument replaced by the file's path) and deletes the file after 60 s.
    private static func runCommandFile(_ script: String, openArguments: [String]) async throws {
        let fileManager = FileManager.default
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw LaunchError(message: "No Application Support directory")
        }
        let directory = support.appendingPathComponent("Bunny/launch", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let file = directory.appendingPathComponent("\(UUID().uuidString).command")
        try Data(script.utf8).write(to: file, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)

        do {
            try await exec("/usr/bin/open", openArguments.map { $0 == SessionLaunchPlanner.scriptPlaceholder ? file.path : $0 })
        } catch {
            try? fileManager.removeItem(at: file)
            throw error
        }
        let lifetime = commandFileLifetime
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(lifetime))
            try? FileManager.default.removeItem(at: file)
        }
    }
}
