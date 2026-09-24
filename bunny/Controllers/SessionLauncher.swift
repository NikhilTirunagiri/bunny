import AppKit
import Foundation
import os

/// Executes `SessionLaunchPlanner` steps to open an agent session in the owner's preferred app.
@MainActor
enum SessionLauncher {
    private static let log = Logger(subsystem: "bunny", category: "SessionLauncher")
    private static let commandFileLifetime: TimeInterval = 60

    private struct LaunchError: Error {
        let message: String
    }

    /// Executes SessionLaunchPlanner steps; on failure falls back to the Terminal plan; last resort copies the resume command to the pasteboard and returns it.
    @discardableResult
    static func open(harness: AgentHarness, sessionID: String, cwd: String) -> String? {
        let cliPath = AgentSettings.cliPath(for: harness)
        let app = AgentSettings.openIn

        if app != .terminal {
            if AgentSettings.isInstalled(app) {
                let steps = SessionLaunchPlanner.plan(app: app, harness: harness, cliPath: cliPath, sessionID: sessionID, cwd: cwd)
                do {
                    try execute(steps)
                    return nil
                } catch {
                    logFailure(app.displayName, error)
                }
            } else {
                logFailure(app.displayName, LaunchError(message: "not installed"))
            }
        }

        let terminalSteps = SessionLaunchPlanner.plan(app: .terminal, harness: harness, cliPath: cliPath, sessionID: sessionID, cwd: cwd)
        do {
            try execute(terminalSteps)
            return nil
        } catch {
            logFailure(OpenInApp.terminal.displayName, error)
        }

        let command = SessionLaunchPlanner.resumeCommand(harness: harness, cliPath: cliPath, sessionID: sessionID, cwd: cwd)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        return command
    }

    private static func logFailure(_ target: String, _ error: Error) {
        let reason = (error as? LaunchError)?.message ?? String(describing: error)
        log.error("Opening \(target, privacy: .public) failed: \(reason, privacy: .public)")
    }

    // MARK: - Steps

    private static func execute(_ steps: [LaunchStep]) throws {
        // Check what can be checked up front, so a failure falls back before anything was opened.
        for step in steps {
            try preflight(step)
        }
        for step in steps {
            switch step {
            case let .runCommandFile(script):
                try runCommandFile(script)
            case let .exec(executable, arguments):
                try exec(executable, arguments)
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

    private static func exec(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Writes `~/Library/Application Support/Bunny/launch/<uuid>.command` (0755), opens it with Terminal and deletes it after 60 s.
    private static func runCommandFile(_ script: String) throws {
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
            try exec("/usr/bin/open", ["-a", "Terminal", file.path])
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
