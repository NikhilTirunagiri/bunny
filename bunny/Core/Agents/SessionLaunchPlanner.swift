import Foundation

/// Actions to take when launching a session in an external application.
enum LaunchStep: Equatable {
    /// Write a .command file with the given script content and open it with Terminal.
    case runCommandFile(script: String)
    /// Execute a process with the given executable and arguments.
    case exec(executable: String, arguments: [String])
    /// Open a URL (typically a deep link to an IDE extension).
    case openURL(String, delay: TimeInterval)
}

/// Planner for how to open an existing Claude Code or Codex session in various applications.
enum SessionLaunchPlanner {
    /// Character set for strict percent-encoding (unreserved characters only).
    private static let strictUnreservedSet = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Escapes a string for safe use in POSIX shell commands using single-quote wrapping.
    /// Plain strings are wrapped in single quotes. Single quotes within the string are escaped
    /// by ending the quote, adding an escaped single quote, and resuming the quote.
    /// Example: "it's" -> "'it'\\''s'"
    static func shellQuote(_ s: String) -> String {
        // Replace each single quote with '\''
        let escaped = s.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    /// Builds a shell command to resume a session in the appropriate CLI.
    /// For claudeCode: "cd '<cwd>' && exec '<cli>' --resume '<id>'"
    /// For codex: "cd '<cwd>' && exec '<cli>' resume '<id>'"
    static func resumeCommand(harness: AgentHarness, cliPath: String, sessionID: String, cwd: String) -> String {
        let quotedCwd = shellQuote(cwd)
        let quotedCli = shellQuote(cliPath)
        let quotedID = shellQuote(sessionID)

        switch harness {
        case .claudeCode:
            return "cd \(quotedCwd) && exec \(quotedCli) --resume \(quotedID)"
        case .codex:
            return "cd \(quotedCwd) && exec \(quotedCli) resume \(quotedID)"
        }
    }

    /// Private helper to generate launch steps for VS Code or Cursor editors.
    private static func editorSteps(
        editorCLI: String,
        scheme: String,
        harness: AgentHarness,
        cliPath: String,
        sessionID: String,
        cwd: String
    ) -> [LaunchStep] {
        if harness == .claudeCode {
            let encodedID = sessionID.addingPercentEncoding(withAllowedCharacters: strictUnreservedSet) ?? sessionID
            let url = "\(scheme)://anthropic.claude-code/open?session=\(encodedID)"
            return [
                .exec(executable: editorCLI, arguments: [cwd]),
                .openURL(url, delay: 1.0)
            ]
        } else {
            let resumeCmd = resumeCommand(harness: harness, cliPath: cliPath, sessionID: sessionID, cwd: cwd)
            let script = "#!/bin/zsh -l\n\(resumeCmd)\n"
            return [
                .exec(executable: editorCLI, arguments: [cwd]),
                .runCommandFile(script: script)
            ]
        }
    }

    /// Plans the steps needed to open a session in the specified application.
    /// Different applications and harnesses require different approaches (direct terminal execution,
    /// IDE extensions, command files, etc.).
    static func plan(app: OpenInApp, harness: AgentHarness, cliPath: String, sessionID: String, cwd: String) -> [LaunchStep] {
        let resumeCmd = resumeCommand(harness: harness, cliPath: cliPath, sessionID: sessionID, cwd: cwd)

        switch app {
        case .terminal:
            let script = "#!/bin/zsh -l\n\(resumeCmd)\n"
            return [.runCommandFile(script: script)]

        case .ghostty:
            return [
                .exec(
                    executable: "/usr/bin/open",
                    arguments: ["-na", "/Applications/Ghostty.app", "--args", "--working-directory=\(cwd)", "-e", "/bin/zsh", "-lc", resumeCmd]
                )
            ]

        case .vscode:
            return editorSteps(
                editorCLI: "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
                scheme: "vscode",
                harness: harness,
                cliPath: cliPath,
                sessionID: sessionID,
                cwd: cwd
            )

        case .cursor:
            return editorSteps(
                editorCLI: "/Applications/Cursor.app/Contents/Resources/app/bin/cursor",
                scheme: "cursor",
                harness: harness,
                cliPath: cliPath,
                sessionID: sessionID,
                cwd: cwd
            )
        }
    }
}
