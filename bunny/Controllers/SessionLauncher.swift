import AppKit
import Foundation
import os

/// What `SessionLauncher.open` ended up doing.
enum SessionLaunchOutcome: Equatable {
    /// The session was opened in this app (the preferred one, or Terminal as the fallback).
    case opened(OpenInApp)
    /// Nothing could be opened; the resume command was copied to the pasteboard. The text explains it for the panel.
    case copiedToPasteboard(String)

    /// One line for the task's activity.
    var activityText: String {
        switch self {
        case let .opened(app): return "Opened in \(app.displayName)"
        case let .copiedToPasteboard(text): return text
        }
    }
}

/// Executes `SessionLaunchPlanner` steps to open an agent session in the owner's preferred app.
@MainActor
enum SessionLauncher {
    private static let log = Logger(subsystem: "bunny", category: "SessionLauncher")
    private static let commandFileLifetime: TimeInterval = 60

    private struct LaunchError: Error {
        let message: String
    }

    /// Executes SessionLaunchPlanner steps; on failure falls back to the Terminal plan; last resort copies the
    /// resume command to the pasteboard. Waits for `/usr/bin/open` to report success before calling it opened.
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

        let app = AgentSettings.openIn
        if app != .terminal {
            if AgentSettings.isInstalled(app) {
                let steps = SessionLaunchPlanner.plan(app: app, harness: harness, cliPath: cliPath, sessionID: sessionID,
                                                      cwd: cwd, model: model, effort: effort)
                do {
                    try await execute(steps)
                    return .opened(app)
                } catch {
                    logFailure(app.displayName, error)
                }
            } else {
                logFailure(app.displayName, LaunchError(message: "not installed"))
            }
        }

        let terminalSteps = SessionLaunchPlanner.plan(app: .terminal, harness: harness, cliPath: cliPath,
                                                      sessionID: sessionID, cwd: cwd, model: model, effort: effort)
        do {
            try await execute(terminalSteps)
            return .opened(.terminal)
        } catch {
            logFailure(OpenInApp.terminal.displayName, error)
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
            case let .runCommandFile(script):
                try await runCommandFile(script)
            case let .exec(executable, arguments):
                try await exec(executable, arguments)
            case let .openURL(string, delay):
                // preflight validated the URL and that an app handles its scheme.
                guard let url = URL(string: string) else { continue }
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
        case let .exec(executable, _):
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
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        guard executable == "/usr/bin/open" else {
            try process.run()
            return
        }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        guard status == 0 else {
            throw LaunchError(message: "open \(arguments.joined(separator: " ")) exited with status \(status)")
        }
    }

    /// Writes `~/Library/Application Support/Bunny/launch/<uuid>.command` (0755), opens it with Terminal and deletes it after 60 s.
    private static func runCommandFile(_ script: String) async throws {
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
            try await exec("/usr/bin/open", ["-a", "Terminal", file.path])
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
